// lib/dashboard/team_management_view.dart - Fixed version

import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';
import 'package:intl/intl.dart';

class TeamManagementView extends StatefulWidget {
  final String managerId;
  final Map<String, dynamic> managerData;

  const TeamManagementView({
    Key? key,
    required this.managerId,
    required this.managerData,
  }) : super(key: key);

  @override
  State<TeamManagementView> createState() => _TeamManagementViewState();
}

class _TeamManagementViewState extends State<TeamManagementView> with SingleTickerProviderStateMixin {
  late TabController _tabController;
  List<Map<String, dynamic>> _teamMembers = [];
  List<Map<String, dynamic>> _attendanceRecords = [];
  bool _isLoading = true;
  DateTime _startDate = DateTime.now().subtract(const Duration(days: 1)); // Yesterday
  DateTime _endDate = DateTime.now(); // Today
  String? _selectedMemberId;

  @override
  void initState() {
    super.initState();
    _tabController = TabController(length: 2, vsync: this);
    _loadTeamData();
  }

  @override
  void dispose() {
    _tabController.dispose();
    super.dispose();
  }

  Future<void> _loadTeamData() async {
    setState(() => _isLoading = true);

    try {
      debugPrint("TeamManagementView: Starting to load team data for manager: ${widget.managerId}");

      // Get line manager document
      String lineManagerId = widget.managerId.startsWith('EMP')
          ? widget.managerId
          : 'EMP${widget.managerId}';

      final lineManagerQuery = await FirebaseFirestore.instance
          .collection('line_managers')
          .where('managerId', isEqualTo: lineManagerId)
          .limit(1)
          .get();

      debugPrint("Looking for line manager with ID: $lineManagerId");

      if (lineManagerQuery.docs.isEmpty) {
        debugPrint("No line manager document found");
        setState(() => _isLoading = false);
        CustomSnackBar.errorSnackBar("Line manager data not found");
        return;
      }

      final lineManagerData = lineManagerQuery.docs.first.data();
      debugPrint("Found line manager data: $lineManagerData");

      final teamMemberNumbers = List<String>.from(lineManagerData['teamMembers'] ?? []);
      debugPrint("Team members: $teamMemberNumbers");

      // Load team members from the MasterSheet collection instead of employees
      _teamMembers = [];
      for (final memberNumber in teamMemberNumbers) {
        debugPrint("Loading member: $memberNumber");

        try {
          // Format the employee ID correctly
          String formattedEmployeeId = 'EMP${memberNumber.toString().padLeft(4, '0')}';
          debugPrint("Trying to load employee with ID: $formattedEmployeeId");

          // IMPORTANT: Get from MasterSheet collection, not employees collection
          final employeeDoc = await FirebaseFirestore.instance
              .collection('MasterSheet')
              .doc('Employee-Data')
              .collection('employees')
              .doc(formattedEmployeeId)
              .get();

          if (employeeDoc.exists) {
            debugPrint("Found employee: ${employeeDoc.id}");
            _teamMembers.add({
              'id': employeeDoc.id,
              'employeeNumber': memberNumber,
              'data': employeeDoc.data(),
            });
          } else {
            debugPrint("No employee found with ID: $formattedEmployeeId");

            // Try without zero padding for larger numbers
            if (int.parse(memberNumber) > 999) {
              String alternativeId = 'EMP$memberNumber';
              debugPrint("Trying alternative ID: $alternativeId");

              final altEmployeeDoc = await FirebaseFirestore.instance
                  .collection('MasterSheet')
                  .doc('Employee-Data')
                  .collection('employees')
                  .doc(alternativeId)
                  .get();

              if (altEmployeeDoc.exists) {
                debugPrint("Found employee with alternative ID: ${altEmployeeDoc.id}");
                _teamMembers.add({
                  'id': altEmployeeDoc.id,
                  'employeeNumber': memberNumber,
                  'data': altEmployeeDoc.data(),
                });
              }
            }
          }
        } catch (e) {
          debugPrint("Error loading member $memberNumber: $e");
        }
      }

      debugPrint("Loaded ${_teamMembers.length} team members out of ${teamMemberNumbers.length}");

      // Load initial attendance (last 2 days)
      await _loadAttendance();

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading team data: $e');
      setState(() => _isLoading = false);
      CustomSnackBar.errorSnackBar("Error loading team data: $e");
    }
  }

  Future<void> _loadAttendance() async {
    setState(() => _isLoading = true);
    _attendanceRecords.clear();

    try {
      // For each team member, get their attendance
      for (final member in _teamMembers) {
        String employeeId = member['id']; // This is EMP1213 format

        // BUT the attendance collection might be using a different ID format
        // We need to find the actual employee document ID from the employees collection

        debugPrint("Looking for attendance for employee: $employeeId");

        try {
          // First, try to find this employee in the employees collection
          final employeeQuery = await FirebaseFirestore.instance
              .collection('employees')
              .where('pin', isEqualTo: member['employeeNumber'])
              .limit(1)
              .get();

          if (employeeQuery.docs.isNotEmpty) {
            final actualEmployeeId = employeeQuery.docs.first.id;
            debugPrint("Found employee in employees collection: $actualEmployeeId");

            // Now get attendance using the actual employee document ID
            final startDateStr = DateFormat('yyyy-MM-dd').format(_startDate);
            final endDateStr = DateFormat('yyyy-MM-dd').format(_endDate);

            final attendanceQuery = await FirebaseFirestore.instance
                .collection('employees')
                .doc(actualEmployeeId)
                .collection('attendance')
                .where('date', isGreaterThanOrEqualTo: startDateStr)
                .where('date', isLessThanOrEqualTo: endDateStr)
                .orderBy('date', descending: true)
                .get();

            debugPrint("Found ${attendanceQuery.docs.length} attendance records for employee $actualEmployeeId");

            for (final doc in attendanceQuery.docs) {
              final data = doc.data();
              _attendanceRecords.add({
                'employeeId': actualEmployeeId,
                'employeeNumber': member['employeeNumber'],
                'employeeName': member['data']['employeeName'] ?? 'Unknown',
                'date': data['date'],
                'checkIn': data['checkIn'],
                'checkOut': data['checkOut'],
                'workStatus': data['workStatus'],
                'totalHours': data['totalHours'],
                'location': data['location'],
              });
            }
          } else {
            debugPrint("Employee not found in employees collection for PIN: ${member['employeeNumber']}");
          }
        } catch (e) {
          debugPrint("Error loading attendance for employee ${member['employeeNumber']}: $e");
        }
      }

      // Sort by date descending
      _attendanceRecords.sort((a, b) => b['date'].compareTo(a['date']));

      debugPrint("Total attendance records loaded: ${_attendanceRecords.length}");

      setState(() => _isLoading = false);
    } catch (e) {
      debugPrint('Error loading attendance: $e');
      setState(() => _isLoading = false);
      CustomSnackBar.errorSnackBar("Error loading attendance: $e");
    }
  }

  void _selectDateRange() async {
    final DateTimeRange? picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime.now().subtract(const Duration(days: 365)),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) {
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: const ColorScheme.light(
              primary: accentColor,
            ),
          ),
          child: child!,
        );
      },
    );

    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      await _loadAttendance();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('My Team'),
        backgroundColor: scaffoldTopGradientClr,
        bottom: TabBar(
          controller: _tabController,
          tabs: const [
            Tab(text: 'Team Members'),
            Tab(text: 'Attendance'),
          ],
        ),
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator(color: accentColor))
          : TabBarView(
        controller: _tabController,
        children: [
          _buildTeamMembersTab(),
          _buildAttendanceTab(),
        ],
      ),
    );
  }

  // In the _buildTeamMembersTab method, update how you access the data:

  Widget _buildTeamMembersTab() {
    if (_teamMembers.isEmpty) {
      return const Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.people_outline, size: 64, color: Colors.grey),
            SizedBox(height: 16),
            Text(
              'No team members found',
              style: TextStyle(fontSize: 16, color: Colors.grey),
            ),
          ],
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: _teamMembers.length,
      itemBuilder: (context, index) {
        final member = _teamMembers[index];
        final memberData = member['data'];

        // Debug print to see what data we have
        debugPrint("Member data for ${member['employeeNumber']}: $memberData");

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: accentColor,
              radius: 25,
              child: Text(
                (memberData['employeeName'] ?? 'Unknown')
                    .substring(0, 1)
                    .toUpperCase(),
                style: const TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              memberData['employeeName'] ?? 'Unknown',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Employee No: ${member['employeeNumber']}'),
                Text('Designation: ${memberData['designation'] ?? 'N/A'}'),
                // Sometimes department might be stored in lineManagerDepartment field
                Text('Department: ${memberData['department'] ?? memberData['lineManagerDepartment'] ?? 'N/A'}'),
              ],
            ),
            trailing: ElevatedButton(
              onPressed: () {
                setState(() {
                  _selectedMemberId = member['id'];
                });
                _tabController.animateTo(1); // Switch to attendance tab
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: accentColor,
              ),
              child: const Text('View Attendance'),
            ),
          ),
        );
      },
    );
  }

  Widget _buildAttendanceTab() {
    return Column(
      children: [
        // Date filter
        Container(
          padding: const EdgeInsets.all(16),
          color: Colors.grey.shade100,
          child: Row(
            children: [
              Expanded(
                child: Text(
                  'From: ${DateFormat('MMM d, yyyy').format(_startDate)} - To: ${DateFormat('MMM d, yyyy').format(_endDate)}',
                  style: const TextStyle(fontSize: 16),
                ),
              ),
              ElevatedButton.icon(
                onPressed: _selectDateRange,
                icon: const Icon(Icons.calendar_today),
                label: const Text('Change Dates'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: accentColor,
                ),
              ),
            ],
          ),
        ),

        // Member filter dropdown
        if (_teamMembers.isNotEmpty)
          Padding(
            padding: const EdgeInsets.all(16),
            child: DropdownButtonFormField<String>(
              value: _selectedMemberId,
              decoration: const InputDecoration(
                labelText: 'Filter by Team Member',
                border: OutlineInputBorder(),
              ),
              items: [
                const DropdownMenuItem(
                  value: null,
                  child: Text('All Team Members'),
                ),
                ..._teamMembers.map((member) {
                  final memberData = member['data'];
                  final employeeName = memberData['employeeName'] ?? 'Unknown';
                  return DropdownMenuItem(
                    value: member['id'],
                    child: Text(employeeName),
                  );
                }),
              ],
              onChanged: (value) {
                setState(() {
                  _selectedMemberId = value;
                });
              },
            ),
          ),

        // Attendance list
        Expanded(
          child: _buildAttendanceList(),
        ),
      ],
    );
  }

  Widget _buildAttendanceList() {
    // Filter attendance records based on selected member
    List<Map<String, dynamic>> filteredRecords = _attendanceRecords;
    if (_selectedMemberId != null) {
      filteredRecords = _attendanceRecords.where((record) {
        return record['employeeId'] == _selectedMemberId;
      }).toList();
    }

    if (filteredRecords.isEmpty) {
      return const Center(
        child: Text(
          'No attendance records found for the selected period',
          style: TextStyle(fontSize: 16, color: Colors.grey),
        ),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(16),
      itemCount: filteredRecords.length,
      itemBuilder: (context, index) {
        final record = filteredRecords[index];
        final checkIn = _formatTime(record['checkIn']);
        final checkOut = _formatTime(record['checkOut']);
        final totalHours = _formatHours(record['totalHours']);
        final workStatus = record['workStatus'] ?? 'Unknown';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Expanded(
                      child: Text(
                        record['employeeName'],
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 16,
                        ),
                      ),
                    ),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                      decoration: BoxDecoration(
                        color: workStatus == 'Completed'
                            ? Colors.green.withOpacity(0.2)
                            : workStatus == 'In Progress'
                            ? Colors.blue.withOpacity(0.2)
                            : Colors.orange.withOpacity(0.2),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Text(
                        workStatus,
                        style: TextStyle(
                          color: workStatus == 'Completed'
                              ? Colors.green
                              : workStatus == 'In Progress'
                              ? Colors.blue
                              : Colors.orange,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  _formatDate(record['date']),
                  style: const TextStyle(
                    fontSize: 14,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Check In: $checkIn'),
                    Text('Check Out: $checkOut'),
                  ],
                ),
                const SizedBox(height: 4),
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Total Hours: $totalHours'),
                    Expanded(
                      child: Text(
                        'Location: ${record['location'] ?? 'Unknown'}',
                        textAlign: TextAlign.right,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  String _formatDate(String date) {
    try {
      final DateTime dateTime = DateTime.parse(date);
      return DateFormat('EEEE, MMM d, yyyy').format(dateTime);
    } catch (e) {
      return date;
    }
  }

  String _formatTime(dynamic time) {
    if (time == null) return 'Not recorded';

    if (time is Timestamp) {
      return DateFormat('h:mm a').format(time.toDate());
    } else if (time is String) {
      try {
        final DateTime dateTime = DateTime.parse(time);
        return DateFormat('h:mm a').format(dateTime);
      } catch (e) {
        return time;
      }
    }

    return 'Invalid time';
  }

  String _formatHours(dynamic hours) {
    if (hours == null) return '0:00';

    if (hours is num) {
      final int totalMinutes = (hours * 60).round();
      final int h = totalMinutes ~/ 60;
      final int m = totalMinutes % 60;
      return '$h:${m.toString().padLeft(2, '0')}';
    }


    return hours.toString();
  }
}

