import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:sqflite/sqflite.dart';

import '../database.dart';
import 'handle.dart';
import 'message.dart';
import '../../helpers/utils.dart';

Chat chatFromJson(String str) {
  final jsonData = json.decode(str);
  return Chat.fromMap(jsonData);
}

String chatToJson(Chat data) {
  final dyn = data.toMap();
  return json.encode(dyn);
}

class Chat {
  int id;
  String guid;
  int style;
  String chatIdentifier;
  bool isArchived;
  String displayName;
  DateTime lastMessageTimestamp;
  List<Handle> participants;

  Chat({
    this.id,
    this.guid,
    this.style,
    this.chatIdentifier,
    this.isArchived,
    this.displayName,
    this.lastMessageTimestamp,
    this.participants
  });

  factory Chat.fromMap(Map<String, dynamic> json) {
    List<Handle> participants = [];
    if (json.containsKey('participants')) {
      (json['participants'] as List<dynamic>).forEach((item) => participants.add(Handle.fromMap(item)));
    }

    return new Chat(
      id: json.containsKey("ROWID") ? json["ROWID"] : null,
      guid: json["guid"],
      style: json['style'],
      chatIdentifier: json.containsKey("chatIdentifier") ? json["chatIdentifier"] : null,
      isArchived: (json["isArchived"] is bool) ? json['isArchived'] : ((json['isArchived'] == 1) ? true : false),
      displayName: json.containsKey("displayName") ? json["displayName"] : null,
      lastMessageTimestamp: json.containsKey("lastMessageTimestamp") ? parseDate(json["lastMessageTimestamp"]) : null,
      participants: participants
    );
  }

  Future<Chat> save([bool updateIfAbsent = true]) async {
    final Database db = await DBProvider.db.database;

    // Try to find an existing chat before saving it
    Chat existing = await Chat.findOne({"guid": this.guid});
    if (existing != null) {
      this.id = existing.id;
    }

    // If it already exists, update it
    if (existing == null) {
      // Remove the ID from the map for inserting
      var map = this.toMap();
      if (map.containsKey("ROWID")) {
        map.remove("ROWID");
      }
      if (map.containsKey("participants")) {
        map.remove("participants");
      }

      this.id = await db.insert("chat", map);
    } else if (updateIfAbsent) {
      await this.update();
    }

    // Save participants to the chat
    for (int i = 0; i < this.participants.length; i++) {
      await this.participants[i].addToChat(this);  
    }
    
    return this;
  }

  Future<Chat> update() async {
    final Database db = await DBProvider.db.database;

    Map<String, dynamic> params = {
      "isArchived": this.isArchived ? 1 : 0,
      "lastMessageTimestamp": (this.lastMessageTimestamp == null) ? null : this.lastMessageTimestamp.millisecondsSinceEpoch
    };

    // Add GUID if we need to update it
    if (this.displayName != null) {
      params.putIfAbsent("displayName", () => this.displayName);
    }
    
    // If it already exists, update it
    if (this.id != null) {
      await db.update("chat", params);
    } else {
      await this.save(false);
    }
    
    return this;
  }

  Future<Chat> addMessage(Message message) async {
    final Database db = await DBProvider.db.database;

    if (message.id == null) {
      await message.save();
    }

    if (this.id == null) {
      await this.save();
    }

    await db.insert("chat_message_join", {
      "chatId": this.id,
      "messageId": message.id
    });

    return this;
  }

  static Future<List<Message>> getMessages(Chat chat) async {
    final Database db = await DBProvider.db.database;

    var res = await db.rawQuery("SELECT"
        " message.ROWID AS ROWID,"
        " message.guid AS guid,"
        " message.handleId AS handleId,"
        " message.text AS text,"
        " message.subject AS subject,"
        " message.country AS country,"
        " message.error AS error,"
        " message.dateCreated AS dateCreated,"
        " message.dateDelivered AS dateDelivered,"
        " message.isFromMe AS isFromMe,"
        " message.isDelayed AS isDelayed,"
        " message.isAutoReply AS isAutoReply,"
        " message.isSystemMessage AS isSystemMessage,"
        " message.isForward AS isForward,"
        " message.isArchived AS isArchived,"
        " message.cacheRoomnames AS cacheRoomnames,"
        " message.isAudioMessage AS isAudioMessage,"
        " message.datePlayed AS datePlayed,"
        " message.itemType AS itemType,"
        " message.groupTitle AS groupTitle,"
        " message.isExpired AS isExpired,"
        " message.associatedMessageGuid AS associatedMessageGuid,"
        " message.associatedMessageType AS associatedMessageType,"
        " message.expressiveSendStyleId AS texexpressiveSendStyleIdt,"
        " message.timeExpressiveSendStyleId AS timeExpressiveSendStyleId"
        " FROM message"
        " JOIN chat_message_join AS cmj ON chat.ROWID = cmj.chatId"
        " JOIN message ON message.ROWID = cmj.messageId"
        " WHERE chat.ROWID = ?;",
      [chat.id]
    );

    return (res.isNotEmpty) ? res.map((c) => Message.fromMap(c)).toList() : [];
  }

  Future<Chat> getParticipants() async {
    final Database db = await DBProvider.db.database;
    
    debugPrint("GETTING PARTICIPANTS");
    var res = await db.rawQuery("SELECT"
        " handle.ROWID AS ROWID,"
        " handle.address AS address,"
        " handle.country AS country,"
        " handle.uncanonicalizedId AS uncanonicalizedId"
        " FROM chat"
        " JOIN chat_handle_join AS chj ON chat.ROWID = chj.chatId"
        " JOIN handle ON handle.ROWID = chj.handleId"
        " WHERE chat.ROWID = ?;",
        [this.id]
    );

    debugPrint(res.toString());

    this.participants = (res.isNotEmpty) ? res.map((c) => Handle.fromMap(c)).toList() : [];
    return this;
  }

  Future removeParticipant(Handle handle) async {
    final Database db = await DBProvider.db.database;
    await db.delete("chat_handle_join", where: "handleId = ?", whereArgs: [handle.id]);
  }

  static Future<Chat> findOne(Map<String, dynamic> filters) async {
    final Database db = await DBProvider.db.database;

    List<String> whereParams = [];
    filters.keys.forEach((filter) => whereParams.add('$filter = ?'));
    List<dynamic> whereArgs = [];
    filters.values.forEach((filter) => whereArgs.add(filter));
    var res = await db.query("chat", where: whereParams.join(" AND "), whereArgs: whereArgs, limit: 1);

    if (res.isEmpty) {
      return null;
    }

    return Chat.fromMap(res.elementAt(0));
  }

  static Future<List<Chat>> find([Map<String, dynamic> filters = const{}]) async {
    final Database db = await DBProvider.db.database;

    List<String> whereParams = [];
    filters.keys.forEach((filter) => whereParams.add('$filter = ?'));
    List<dynamic> whereArgs = [];
    filters.values.forEach((filter) => whereArgs.add(filter));

    var res = await db.query(
      "chat", where: (whereParams.length > 0) ? whereParams.join(" AND ") : null , whereArgs: (whereArgs.length > 0) ? whereArgs : null);
    return (res.isNotEmpty) ? res.map((c) => Chat.fromMap(c)).toList() : [];
  }

  Map<String, dynamic> toMap() => {
    "ROWID": id,
    "guid": guid,
    "style": style,
    "chatIdentifier": chatIdentifier,
    "isArchived": isArchived ? 1 : 0,
    "displayName": displayName,
    "lastMessageTimestamp": (lastMessageTimestamp == null) ? null : lastMessageTimestamp.millisecondsSinceEpoch,
    "participants": participants.map((item) => item.toMap())
  };
}