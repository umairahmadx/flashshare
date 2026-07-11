class UploadInit {
  final String type;
  final String? uploadUrl;
  final Map<String, dynamic>? headers;
  final String? uploadId;
  final String r2Key;
  final int? partSize;
  final int? totalParts;
  final Map<String, String>? initialUrls;
  final String? ownerToken;

  UploadInit({
    required this.type,
    this.uploadUrl,
    this.headers,
    this.uploadId,
    required this.r2Key,
    this.partSize,
    this.totalParts,
    this.initialUrls,
    this.ownerToken,
  });

  factory UploadInit.fromJson(Map<String, dynamic> j) {
    final urls = j['initial_urls'];
    return UploadInit(
      type: j['type'] as String,
      uploadUrl: j['upload_url'] as String?,
      headers: j['headers'] as Map<String, dynamic>?,
      uploadId: j['upload_id'] as String?,
      r2Key: j['r2_key'] as String,
      partSize: j['part_size'] as int?,
      totalParts: j['total_parts'] as int?,
      initialUrls: urls == null
          ? null
          : (urls as Map).map((k, v) => MapEntry(k as String, v as String)),
      ownerToken: j['owner_token'] as String?,
    );
  }
}

class PartEtag {
  final int partNumber;
  final String etag;
  PartEtag(this.partNumber, this.etag);
}

class FileRecord {
  final String id;
  final String url;
  final String rawUrl;
  final String filename;
  final int size;
  final String? humanSize;
  final String? expiresAt;
  final String ownerToken;

  FileRecord({
    required this.id,
    required this.url,
    required this.rawUrl,
    required this.filename,
    required this.size,
    this.humanSize,
    this.expiresAt,
    required this.ownerToken,
  });

  factory FileRecord.fromJson(Map<String, dynamic> j, String ownerToken) {
    return FileRecord(
      id: j['id'] as String,
      url: j['url'] as String,
      rawUrl: j['raw_url'] as String,
      filename: j['filename'] as String,
      size: j['size'] as int,
      humanSize: j['human_size'] as String?,
      expiresAt: j['expires_at'] as String?,
      ownerToken: ownerToken,
    );
  }
}

class Collection {
  final String id;
  final String url;
  final String? expiresAt;
  final String ownerToken;

  Collection({
    required this.id,
    required this.url,
    this.expiresAt,
    required this.ownerToken,
  });

  factory Collection.fromJson(Map<String, dynamic> j, String ownerToken) {
    return Collection(
      id: j['id'] as String,
      url: j['url'] as String,
      expiresAt: j['expires_at'] as String?,
      ownerToken: ownerToken,
    );
  }
}

class HistoryEntry {
  final String id;
  final String url;
  final String filename;
  final int size;
  final String? expiresAt;
  final String ownerToken;
  final String kind; // 'file' | 'collection'
  final int createdAt;

  HistoryEntry({
    required this.id,
    required this.url,
    required this.filename,
    required this.size,
    this.expiresAt,
    required this.ownerToken,
    required this.kind,
    required this.createdAt,
  });

  Map<String, dynamic> toJson() => {
        'id': id,
        'url': url,
        'filename': filename,
        'size': size,
        'expires_at': expiresAt,
        'owner_token': ownerToken,
        'kind': kind,
        'created_at': createdAt,
      };

  factory HistoryEntry.fromJson(Map<String, dynamic> j) => HistoryEntry(
        id: j['id'] as String,
        url: j['url'] as String,
        filename: j['filename'] as String,
        size: j['size'] as int,
        expiresAt: j['expires_at'] as String?,
        ownerToken: j['owner_token'] as String,
        kind: j['kind'] as String,
        createdAt: j['created_at'] as int,
      );
}

String guessContentType(String filename) {
  final ext = filename.contains('.')
      ? filename.split('.').last.toLowerCase()
      : '';
  const map = {
    'jpg': 'image/jpeg', 'jpeg': 'image/jpeg', 'png': 'image/png',
    'gif': 'image/gif', 'webp': 'image/webp', 'bmp': 'image/bmp',
    'pdf': 'application/pdf', 'txt': 'text/plain', 'md': 'text/markdown',
    'csv': 'text/csv', 'json': 'application/json', 'xml': 'application/xml',
    'mp4': 'video/mp4', 'mov': 'video/quicktime', 'webm': 'video/webm',
    'avi': 'video/x-msvideo', 'mkv': 'video/x-matroska',
    'mp3': 'audio/mpeg', 'wav': 'audio/wav', 'ogg': 'audio/ogg', 'm4a': 'audio/mp4',
    'zip': 'application/zip', 'rar': 'application/x-rar-compressed',
    '7z': 'application/x-7z-compressed', 'tar': 'application/x-tar',
    'doc': 'application/msword',
    'docx': 'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls': 'application/vnd.ms-excel',
    'xlsx': 'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    'ppt': 'application/vnd.ms-powerpoint',
    'pptx': 'application/vnd.openxmlformats-officedocument.presentationml.presentation',
  };
  return map[ext] ?? 'application/octet-stream';
}
