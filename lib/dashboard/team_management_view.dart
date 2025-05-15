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
      debugPrint("TeamManagementView: Starting to load team data");
      debugPrint("Manager ID received: ${widget.managerId}");
      debugPrint("Manager Data: ${widget.managerData}");

      // Initialize empty list for team members
      _teamMembers = [];

      // Query line_managers collection to find this manager's document
      QuerySnapshot lineManagerSnapshot;

      // Try different formats to find the line manager document
      try {
        // First try with the exact managerId
        lineManagerSnapshot = await FirebaseFirestore.instance
            .collection('line_managers')
            .where('managerId', isEqualTo: widget.managerId)
            .limit(1)
            .get();

        // If not found, try with EMP prefix
        if (lineManagerSnapshot.docs.isEmpty && !widget.managerId.startsWith('EMP')) {
          debugPrint("Trying with EMP prefix: EMP${widget.managerId}");
          lineManagerSnapshot = await FirebaseFirestore.instance
              .collection('line_managers')
              .where('managerId', isEqualTo: 'EMP${widget.managerId}')
              .limit(1)
              .get();
        }

        // If still not found, try without EMP prefix if it has one
        if (lineManagerSnapshot.docs.isEmpty && widget.managerId.startsWith('EMP')) {
          String withoutPrefix = widget.managerId.substring(3);
          debugPrint("Trying without EMP prefix: $withoutPrefix");
          lineManagerSnapshot = await FirebaseFirestore.instance
              .collection('line_managers')
              .where('managerId', isEqualTo: withoutPrefix)
              .limit(1)
              .get();
        }
      } catch (e) {
        debugPrint("Error querying line managers: $e");
        setState(() => _isLoading = false);
        CustomSnackBar.errorSnackBar("Error finding manager data: $e");
        return;
      }

      if (lineManagerSnapshot.docs.isEmpty) {
        debugPrint("No line manager document found for: ${widget.managerId}");
        setState(() => _isLoading = false);
        CustomSnackBar.errorSnackBar("Line manager data not found");
        return;
      }

      // Get the line manager data
      final lineManagerDoc = lineManagerSnapshot.docs.first;
      final lineManagerData = lineManagerDoc.data() as Map<String, dynamic>;
      debugPrint("Found line manager data: $lineManagerData");

      // Get team member IDs
      final teamMemberIds = List<String>.from(lineManagerData['teamMembers'] ?? []);
      debugPrint("Team member IDs: $teamMemberIds");

      if (teamMemberIds.isEmpty) {
        debugPrint("No team members found for this manager");
        setState(() => _isLoading = false);
        return;
      }

      // Load employee data for each team member
      for (String memberId in teamMemberIds) {
        try {
          debugPrint("Loading employee data for member ID: $memberId");

          // Try different formats to find the employee
          DocumentSnapshot? employeeDoc;
          Map<String, dynamic>? employeeData;

          // Try multiple collections and formats

          // First try employees collection with various ID formats
          List<String> possibleIds = [
            'EMP${memberId.padLeft(4, '0')}',  // EMP0001
            'EMP$memberId',                     // EMP1213
            memberId,                           // Just the number
          ];

          // Try employees collection first
          for (String tryId in possibleIds) {
            try {
              debugPrint("Trying employees collection with ID: $tryId");
              employeeDoc = await FirebaseFirestore.instance
                  .collection('employees')
                  .doc(tryId)
                  .get();

              if (employeeDoc.exists) {
                employeeData = employeeDoc.data() as Map<String, dynamic>;
                debugPrint("Found in employees collection with ID: $tryId");
                debugPrint("Employee data: $employeeData");
                break;
              }
            } catch (e) {
              debugPrint("Not found with ID $tryId in employees collection");
            }
          }

          // If not found in employees, try MasterSheet
          if (employeeDoc == null || !employeeDoc.exists) {
            for (String tryId in possibleIds) {
              try {
                debugPrint("Trying MasterSheet with ID: $tryId");
                employeeDoc = await FirebaseFirestore.instance
                    .collection('MasterSheet')
                    .doc('Employee-Data')
                    .collection('employees')
                    .doc(tryId)
                    .get();

                if (employeeDoc.exists) {
                  employeeData = employeeDoc.data() as Map<String, dynamic>;
                  debugPrint("Found in MasterSheet with ID: $tryId");
                  debugPrint("MasterSheet data: $employeeData");
                  break;
                }
              } catch (e) {
                debugPrint("Not found with ID $tryId in MasterSheet");
              }
            }
          }

          // If still not found, try query by PIN in employees collection
          if (employeeDoc == null || !employeeDoc.exists) {
            debugPrint("Trying to find by PIN: $memberId");

            QuerySnapshot pinQuery = await FirebaseFirestore.instance
                .collection('employees')
                .where('pin', isEqualTo: memberId)
                .limit(1)
                .get();

            if (pinQuery.docs.isNotEmpty) {
              employeeDoc = pinQuery.docs.first;
              employeeData = employeeDoc.data() as Map<String, dynamic>;
              debugPrint("Found by PIN query");
              debugPrint("Employee data: $employeeData");
            }
          }

          if (employeeDoc != null && employeeDoc.exists && employeeData != null) {
            // Add the found employee
            _teamMembers.add({
              'id': employeeDoc.id,
              'employeeNumber': memberId,
              'data': employeeData,
            });
            debugPrint("Added team member: ${employeeDoc.id} - ${employeeData['employeeName'] ?? employeeData['name'] ?? 'Unknown'}");
          } else {
            debugPrint("Employee not found for ID: $memberId - adding placeholder");

            // Add a placeholder with correct field names
            _teamMembers.add({
              'id': memberId,
              'employeeNumber': memberId,
              'data': {
                'employeeName': 'Employee $memberId',  // Use 'employeeName' not 'name'
                'name': 'Employee $memberId',          // Include both for compatibility
                'designation': 'Unknown',
                'department': lineManagerData['department'] ?? 'Unknown',
                'lineManagerDepartment': lineManagerData['department'] ?? 'Unknown',
              },
            });
          }

        } catch (e) {
          debugPrint("Error processing team member $memberId: $e");
          // Add placeholder even on error
          _teamMembers.add({
            'id': memberId,
            'employeeNumber': memberId,
            'data': {
              'employeeName': 'Employee $memberId (Error)',
              'name': 'Employee $memberId (Error)',
              'designation': 'Error loading',
              'department': 'Unknown',
              'lineManagerDepartment': 'Unknown',
            },
          });
        }
      }

      debugPrint("Successfully loaded ${_teamMembers.length} team members");

      // Load attendance for the default date range
      await _loadAttendance();

      setState(() => _isLoading = false);

    } catch (e) {
      debugPrint('Error in _loadTeamData: $e');
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

        // Fix the field names to match your database structure
        String employeeName = memberData['employeeName'] ??
            memberData['name'] ??
            'Unknown';

        String designation = memberData['designation'] ?? 'N/A';

        String department = memberData['department'] ??
            memberData['lineManagerDepartment'] ??
            'N/A';

        return Card(
          margin: const EdgeInsets.only(bottom: 12),
          elevation: 2,
          child: ListTile(
            contentPadding: const EdgeInsets.all(16),
            leading: CircleAvatar(
              backgroundColor: accentColor,
              radius: 25,
              child: Text(
                employeeName.substring(0, 1).toUpperCase(),
                style: const TextStyle(
                    color: Colors.white, fontSize: 20, fontWeight: FontWeight.bold),
              ),
            ),
            title: Text(
              employeeName,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
            ),
            subtitle: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: 4),
                Text('Employee No: ${member['employeeNumber']}'),
                Text('Designation: $designation'),
                Text('Department: $department'),
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

