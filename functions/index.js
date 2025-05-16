// functions/index.js (or create this file if it doesn't exist)

const functions = require("firebase-functions");
const admin = require("firebase-admin");
admin.initializeApp();

// Send notification when a check-out request status changes
exports.sendCheckOutRequestNotification = functions.firestore
    .document('check_out_requests/{requestId}')
    .onUpdate((change, context) => {
        const newValue = change.after.data();
        const previousValue = change.before.data();

        // Only send notification if status changed
        if (newValue.status === previousValue.status) {
            console.log('Status did not change, skipping notification');
            return null;
        }

        // Get the employee ID from the request
        const employeeId = newValue.employeeId;
        const requestType = newValue.requestType || 'check-out'; // Default for backward compatibility

        // Format the request type for display - ensuring proper capitalization
        const displayType = requestType === 'check-in' ? 'Check-In' : 'Check-Out';

        return admin.firestore().collection('fcm_tokens').doc(employeeId).get()
            .then(tokenDoc => {
                if (!tokenDoc.exists) {
                    console.log(`No FCM token found for employee ${employeeId}`);
                    return null;
                }

                const token = tokenDoc.data().token;
                if (!token) {
                    console.log(`FCM token is null for employee ${employeeId}`);
                    return null;
                }

                // Create notification based on status
                let notification;
                if (newValue.status === 'approved') {
                    notification = {
                        title: `${displayType} Request Approved`,
                        body: `Your request to ${requestType.replace('-', ' ')} has been approved.`,
                    };
                } else if (newValue.status === 'rejected') {
                    notification = {
                        title: `${displayType} Request Rejected`,
                        body: `Your request to ${requestType.replace('-', ' ')} has been rejected.`,
                    };
                } else {
                    console.log(`Unknown status: ${newValue.status}`);
                    return null;
                }

                // Add data payload
                const payload = {
                    notification,
                    data: {
                        type: 'check_out_request_update',
                        requestId: context.params.requestId,
                        status: newValue.status,
                        employeeId: employeeId,
                        requestType: requestType,
                        message: newValue.responseMessage || '',
                        click_action: 'FLUTTER_NOTIFICATION_CLICK',
                    },
                    token: token,
                    // Add high priority for Android
                    android: {
                        priority: "high",
                        notification: {
                            sound: "default",
                            priority: "high",
                            channel_id: "check_requests_channel"
                        }
                    },
                    // Add important settings for iOS
                    apns: {
                        payload: {
                            aps: {
                                sound: "default",
                                badge: 1,
                                content_available: true,
                                interruption_level: "time-sensitive"
                            }
                        }
                    }
                };

                // Send the notification
                console.log(`Sending notification to ${employeeId} with token ${token}`);
                return admin.messaging().send(payload);
            })
            .catch(error => {
                console.error('Error sending notification:', error);
                return null;
            });
    });

// Send notification when a new check-out request is created
exports.sendNewRequestNotification = functions.firestore
    .document('check_out_requests/{requestId}')
    .onCreate((snapshot, context) => {
        const requestData = snapshot.data();

        // Get the line manager ID from the request
        const lineManagerId = requestData.lineManagerId;
        const requestType = requestData.requestType || 'check-out'; // Default for backward compatibility

        // Format the request type for display - ensuring proper capitalization
        const displayType = requestType === 'check-in' ? 'Check-In' : 'Check-Out';

        // Try multiple formats for manager ID
        const managerIds = [
            lineManagerId,
            lineManagerId.startsWith('EMP') ? lineManagerId.substring(3) : `EMP${lineManagerId}`
        ];

        // Function to send notification with token
        const sendNotificationWithToken = (token) => {
            // Create notification
            const notification = {
                title: `New ${displayType} Request`,
                body: `${requestData.employeeName} has requested to ${requestType.replace('-', ' ')} from an offsite location.`,
            };

            // Add data payload
            const payload = {
                notification,
                data: {
                    type: 'new_check_out_request',
                    requestId: context.params.requestId,
                    employeeId: requestData.employeeId,
                    employeeName: requestData.employeeName,
                    locationName: requestData.locationName,
                    requestType: requestType,
                    click_action: 'FLUTTER_NOTIFICATION_CLICK',
                },
                token: token,
                // Add high priority for Android
                android: {
                    priority: "high",
                    notification: {
                        sound: "default",
                        priority: "high",
                        channel_id: "check_requests_channel"
                    }
                },
                // Add important settings for iOS
                apns: {
                    payload: {
                        aps: {
                            sound: "default",
                            badge: 1,
                            content_available: true,
                            interruption_level: "time-sensitive"
                        }
                    }
                }
            };

            // Send the notification
            console.log(`Sending notification to manager with token ${token}`);
            return admin.messaging().send(payload);
        };

        // Try to find token for any of the manager IDs
        const findAndSendNotification = async () => {
            for (const managerId of managerIds) {
                try {
                    const tokenDoc = await admin.firestore().collection('fcm_tokens').doc(managerId).get();

                    if (tokenDoc.exists) {
                        const token = tokenDoc.data().token;
                        if (token) {
                            console.log(`Found token for manager ${managerId}`);
                            return sendNotificationWithToken(token);
                        }
                    }
                } catch (err) {
                    console.log(`Error checking token for ${managerId}: ${err}`);
                }
            }

            console.log(`No FCM token found for any manager ID: ${managerIds.join(', ')}`);
            return null;
        };

        return findAndSendNotification()
            .catch(error => {
                console.error('Error in send notification process:', error);
                return null;
            });
    });

// Update FCM token when it changes
exports.storeUserFcmToken = functions.https.onCall((data, context) => {
    const userId = data.userId;
    const token = data.token;

    if (!userId || !token) {
        throw new functions.https.HttpsError(
            'invalid-argument',
            'User ID and token are required'
        );
    }

    return admin.firestore().collection('fcm_tokens').doc(userId).set({
        token: token,
        updatedAt: admin.firestore.FieldValue.serverTimestamp(),
    })
        .then(() => {
            return {success: true};
        })
        .catch(error => {
            console.error('Error storing FCM token:', error);
            throw new functions.https.HttpsError('internal', error.message);
        });
});

// Also subscribe manager to topic for added reliability
exports.subscribeManagerToTopic = functions.firestore
    .document('line_managers/{managerId}')
    .onCreate((snapshot, context) => {
        const data = snapshot.data();
        const managerId = data.managerId;

        if (!managerId) {
            console.log('No managerId found in new line_managers document');
            return null;
        }

        // Get manager's token
        return admin.firestore().collection('fcm_tokens').doc(managerId).get()
            .then(tokenDoc => {
                if (!tokenDoc.exists) {
                    console.log(`No FCM token found for manager ${managerId}`);
                    return null;
                }

                const token = tokenDoc.data().token;
                if (!token) {
                    console.log(`FCM token is null for manager ${managerId}`);
                    return null;
                }

                // Subscribe to manager topic
                const topicName = `manager_${managerId}`;
                return admin.messaging().subscribeToTopic(token, topicName)
                    .then(response => {
                        console.log(`Successfully subscribed to topic: ${topicName}`);
                        return response;
                    });
            })
            .catch(error => {
                console.error('Error subscribing to topic:', error);
                return null;
            });
    });