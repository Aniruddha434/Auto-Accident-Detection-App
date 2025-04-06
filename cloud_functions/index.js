const functions = require('firebase-functions');
const admin = require('firebase-admin');
const twilio = require('twilio');

// Initialize Firebase Admin
admin.initializeApp();

// Your Twilio credentials - store these in Firebase environment variables
const accountSid = functions.config().twilio.sid;
const authToken = functions.config().twilio.token;
const twilioNumber = functions.config().twilio.number;

// Initialize Twilio client
const twilioClient = twilio(accountSid, authToken);

// Cloud Function for sending SMS messages
exports.sendEmergencySMS = functions.https.onCall(async (data, context) => {
  // Check if the user is authenticated
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'The function must be called while authenticated.'
    );
  }

  try {
    const { to, message } = data;
    
    if (!to || !message) {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'The function requires "to" and "message" parameters.'
      );
    }

    // Send the SMS via Twilio
    const result = await twilioClient.messages.create({
      body: message,
      from: twilioNumber,
      to: to
    });

    // Return success result
    return {
      success: true,
      messageId: result.sid
    };
  } catch (error) {
    console.error('Error sending SMS:', error);
    throw new functions.https.HttpsError(
      'internal',
      'An error occurred while sending the SMS.',
      error
    );
  }
});

// Trigger function to automatically send emergency SMS when a new alert is created
exports.processEmergencyAlerts = functions.firestore
  .document('emergency_alerts/{alertId}')
  .onCreate(async (snapshot, context) => {
    try {
      const alertData = snapshot.data();
      
      if (!alertData.sent && alertData.recipients && alertData.recipients.length > 0) {
        const message = alertData.message;
        const recipients = alertData.recipients;
        
        // Send SMS to all recipients
        const results = await Promise.all(
          recipients.map(async (phoneNumber) => {
            try {
              const result = await twilioClient.messages.create({
                body: message,
                from: twilioNumber,
                to: phoneNumber
              });
              
              console.log(`SMS sent to ${phoneNumber}, SID: ${result.sid}`);
              return { phoneNumber, success: true, sid: result.sid };
            } catch (err) {
              console.error(`Failed to send SMS to ${phoneNumber}:`, err);
              return { phoneNumber, success: false, error: err.message };
            }
          })
        );
        
        // Update the alert document to mark it as sent
        await snapshot.ref.update({
          sent: true,
          sentTimestamp: admin.firestore.FieldValue.serverTimestamp(),
          deliveryResults: results
        });
        
        return { success: true, results };
      }
      
      return { success: false, reason: 'Alert already sent or no recipients' };
    } catch (error) {
      console.error('Error processing emergency alert:', error);
      return { success: false, error: error.message };
    }
  }); 