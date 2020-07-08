import 'dart:io';

import 'package:bluebubble_messages/helpers/attachment_downloader.dart';
import 'package:bluebubble_messages/layouts/widgets/message_widget/message_content/message_attachment.dart';
import 'package:bluebubble_messages/managers/settings_manager.dart';
import 'package:bluebubble_messages/repository/models/attachment.dart';
import 'package:bluebubble_messages/repository/models/message.dart';
import 'package:bluebubble_messages/socket_manager.dart';
import 'package:flutter/material.dart';
import 'package:mime_type/mime_type.dart';
import 'package:path/path.dart';

class MessageAttachments extends StatefulWidget {
  MessageAttachments({
    Key key,
    @required this.message,
    @required this.attachments,
  }) : super(key: key);
  final Message message;
  final List<Attachment> attachments;

  @override
  _MessageAttachmentsState createState() => _MessageAttachmentsState();
}

class _MessageAttachmentsState extends State<MessageAttachments>
    with TickerProviderStateMixin {
  Map<String, dynamic> _attachments = new Map();

  @override
  void initState() {
    super.initState();
    // getAttachmentsFuture = Message.getAttachments(widget.message);
    for (Attachment attachment in widget.attachments) {
      initForAttachment(attachment);
    }
    debugPrint("initing state");
  }

  void initForAttachment(Attachment attachment) {
    String appDocPath = SettingsManager().appDocDir.path;
    String pathName =
        "$appDocPath/attachments/${attachment.guid}/${attachment.transferName}";

    /**
           * Case 1: If the file exists (we can get the type), add the file to the chat's attachments
           * Case 2: If the attachment is currently being downloaded, get the AttachmentDownloader object and add it to the chat's attachments
           * Case 3: If the attachment is a text-based one, automatically auto-download
           * Case 4: Otherwise, add the attachment, as is, meaning it needs to be downloaded
           */

    if (FileSystemEntity.typeSync(pathName) != FileSystemEntityType.notFound) {
      _attachments[attachment.guid] = File(pathName);
    } else if (SocketManager()
        .attachmentDownloaders
        .containsKey(attachment.guid)) {
      _attachments[attachment.guid] =
          SocketManager().attachmentDownloaders[attachment.guid];
    } else if (attachment.mimeType == null ||
        attachment.mimeType.startsWith("text/")) {
      AttachmentDownloader downloader =
          new AttachmentDownloader(attachment, widget.message);
      _attachments[attachment.guid] = downloader;
    } else {
      _attachments[attachment.guid] = attachment;
    }
  }

  @override
  Widget build(BuildContext context) {
    return Row(
      mainAxisAlignment: widget.message.isFromMe
          ? MainAxisAlignment.end
          : MainAxisAlignment.start,
      children: <Widget>[
        Padding(
          padding: EdgeInsets.symmetric(horizontal: 10.0),
          child: Column(
            children: _buildAttachments(),
          ),
        ),
      ],
    );
  }

  List<Widget> _buildAttachments() {
    List<Widget> content = <Widget>[];
    for (Attachment attachment in widget.attachments) {
      content.add(
        MessageAttachment(
          message: widget.message,
          attachment: attachment,
          content: _attachments[attachment.guid],
          updateAttachment: () {
            initForAttachment(attachment);
            // setState(() {});
          },
        ),
      );
    }
    return content;
  }

  String getMimeType(File attachment) {
    String mimeType = mime(basename(attachment.path));
    if (mimeType == null) return "";
    mimeType = mimeType.substring(0, mimeType.indexOf("/"));
    return mimeType;
  }
}