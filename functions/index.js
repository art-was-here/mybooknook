const functions = require('firebase-functions');
const admin = require('firebase-admin');
admin.initializeApp();

exports.sendPushNotification = functions.firestore
    .document('fcm_messages/{messageId}')
    .onCreate(async (snap, context) => {
        const message = snap.data();
        
        try {
            await admin.messaging().send({
                token: message.token,
                notification: message.notification,
                data: message.data,
            });
            
            // Delete the message after sending
            await snap.ref.delete();
            
            return null;
        } catch (error) {
            console.error('Error sending message:', error);
            return null;
        }
    }); 