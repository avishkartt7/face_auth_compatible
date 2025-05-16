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
                        title: 'Check-Out Request Approved',
                        body: 'Your request to check out has been approved.',
                    };
                } else if (newValue.status === 'rejected') {
                    notification = {
                        title: 'Check-Out Request Rejected',
                        body: 'Your request to check out has been rejected.',
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
                        message: newValue.responseMessage || '',
                        click_action: 'FLUTTER_NOTIFICATION_CLICK',
                    },
                    token: token,
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

        return admin.firestore().collection('fcm_tokens').doc(lineManagerId).get()
            .then(tokenDoc => {
                if (!tokenDoc.exists) {
                    console.log(`No FCM token found for manager ${lineManagerId}`);
                    return null;
                }

                const token = tokenDoc.data().token;
                if (!token) {
                    console.log(`FCM token is null for manager ${lineManagerId}`);
                    return null;
                }

                // Create notification
                const notification = {
                    title: 'New Check-Out Request',
                    body: `${requestData.employeeName} has requested to check out from an offsite location.`,
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
                        click_action: 'FLUTTER_NOTIFICATION_CLICK',
                    },
                    token: token,
                };

                // Send the notification
                console.log(`Sending notification to manager ${lineManagerId} with token ${token}`);
                return admin.messaging().send(payload);
            })
            .catch(error => {
                console.error('Error sending notification:', error);
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