import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:face_auth_compatible/constants/theme.dart';
import 'package:face_auth_compatible/model/user_model.dart';
import 'package:face_auth_compatible/register_face/register_face_view.dart';
import 'package:face_auth_compatible/common/utils/extensions/size_extension.dart';
import 'package:face_auth_compatible/common/utils/custom_snackbar.dart';

class UserManagementView extends StatefulWidget {
  const UserManagementView({Key? key}) : super(key: key);

  @override
  State<UserManagementView> createState() => _UserManagementViewState();
}

class _UserManagementViewState extends State<UserManagementView> {
  @override
  Widget build(BuildContext context) {
    CustomSnackBar.context = context;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        centerTitle: true,
        backgroundColor: appBarColor,
        title: const Text("User Management"),
        elevation: 0,
      ),
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              scaffoldTopGradientClr,
              scaffoldBottomGradientClr,
            ],
          ),
        ),
        child: Column(
          children: [
            SizedBox(height: 0.15.sh),
            Padding(
              padding: EdgeInsets.symmetric(horizontal: 0.05.sw),
              child: GestureDetector(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const RegisterFaceView(),
                    ),
                  );
                },
                child: Container(
                  decoration: BoxDecoration(
                    color: buttonColor,
                    borderRadius: BorderRadius.circular(0.02.sh),
                  ),
                  child: Padding(
                    padding: EdgeInsets.all(0.03.sw),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Padding(
                          padding: EdgeInsets.only(left: 0.03.sw),
                          child: Text(
                            "Register New User",
                            style: TextStyle(
                              color: primaryBlack,
                              fontSize: 0.025.sh,
                              fontWeight: FontWeight.w500,
                            ),
                          ),
                        ),
                        CircleAvatar(
                          radius: 0.03.sh,
                          backgroundColor: accentColor,
                          child: const Icon(
                            Icons.person_add,
                            color: buttonColor,
                          ),
                        )
                      ],
                    ),
                  ),
                ),
              ),
            ),
            SizedBox(height: 0.04.sh),
            Expanded(
              child: _buildUserList(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildUserList() {
    return StreamBuilder<QuerySnapshot>(
      stream: FirebaseFirestore.instance.collection("users").snapshots(),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Center(
            child: CircularProgressIndicator(color: accentColor),
          );
        }

        if (snapshot.hasError) {
          return Center(
            child: Text(
              "Error loading users: ${snapshot.error}",
              style: const TextStyle(color: primaryWhite),
            ),
          );
        }

        if (!snapshot.hasData || snapshot.data!.docs.isEmpty) {
          return const Center(
            child: Text(
              "No users registered yet",
              style: TextStyle(color: primaryWhite, fontSize: 18),
            ),
          );
        }

        return ListView.builder(
          padding: EdgeInsets.symmetric(horizontal: 0.05.sw),
          itemCount: snapshot.data!.docs.length,
          itemBuilder: (context, index) {
            var doc = snapshot.data!.docs[index];
            UserModel user = UserModel.fromJson(doc.data() as Map<String, dynamic>);

            return Card(
              margin: EdgeInsets.only(bottom: 0.02.sh),
              color: primaryWhite.withOpacity(0.9),
              child: ListTile(
                contentPadding: const EdgeInsets.all(12),
                title: Text(
                  user.name ?? "Unknown User",
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                  ),
                ),
                subtitle: Text(
                  "Registered: ${_formatDate(user.registeredOn)}",
                  style: TextStyle(
                    color: primaryBlack.withOpacity(0.6),
                  ),
                ),
                trailing: IconButton(
                  icon: const Icon(Icons.delete, color: Colors.red),
                  onPressed: () => _confirmDeleteUser(context, user),
                ),
              ),
            );
          },
        );
      },
    );
  }

  String _formatDate(int? timestamp) {
    if (timestamp == null) return "Unknown";
    final DateTime date = DateTime.fromMillisecondsSinceEpoch(timestamp);
    return "${date.day}/${date.month}/${date.year}";
  }

  void _confirmDeleteUser(BuildContext context, UserModel user) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("Delete User"),
        content: Text("Are you sure you want to delete ${user.name}?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text("Cancel", style: TextStyle(color: accentColor)),
          ),
          TextButton(
            onPressed: () {
              FirebaseFirestore.instance
                  .collection("users")
                  .doc(user.id)
                  .delete()
                  .then((_) {
                Navigator.pop(context);
                CustomSnackBar.successSnackBar("User deleted successfully");
              }).catchError((e) {
                Navigator.pop(context);
                CustomSnackBar.errorSnackBar("Error deleting user: $e");
              });
            },
            child: const Text("Delete", style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );
  }
}