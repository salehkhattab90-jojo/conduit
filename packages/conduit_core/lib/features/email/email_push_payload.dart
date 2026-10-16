/// The data block of an Email push notification.
library;

/// Android notification channel the server names in every Email push
/// (`android.notification.channel_id`). The app must create a channel with
/// exactly this id, or Android files background pushes under a fallback one.
const String emailNotificationChannelId = 'email_significant';

/// `data.type` of an Email push.
const String emailPushType = 'email';

/// An Email push, decoded from its FCM `data` map.
final class EmailPushPayload {
  const EmailPushPayload({this.messageId});

  /// The message to open on tap, or null to open the Email section only (a
  /// "reconnect your mailbox" push carries an empty id).
  final String? messageId;

  /// Null when [data] is not an Email push.
  static EmailPushPayload? fromData(Map<String, Object?> data) {
    if (data['type'] != emailPushType) return null;
    final id = data['email_message_id'];
    return EmailPushPayload(
      messageId: id is String && id.trim().isNotEmpty ? id.trim() : null,
    );
  }
}
