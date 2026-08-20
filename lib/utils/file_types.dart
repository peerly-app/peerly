import 'package:flutter/material.dart';

const imageExtensions = <String>{
  'jpg',
  'jpeg',
  'png',
  'gif',
  'webp',
  'heic',
  'heif',
  'bmp',
};
const videoExtensions = <String>{'mp4', 'mov', 'm4v', 'webm', 'mkv', 'avi'};
const audioExtensions = <String>{'mp3', 'wav', 'm4a', 'aac', 'ogg', 'flac'};
const archiveExtensions = <String>{'zip'};
const spreadsheetExtensions = <String>{'xls', 'xlsx', 'ods', 'csv'};
const presentationExtensions = <String>{'ppt', 'pptx', 'odp'};
const documentExtensions = <String>{'pdf', 'doc', 'docx', 'txt', 'rtf', 'odt'};

final allowedFileExtensions = List<String>.unmodifiable({
  ...imageExtensions,
  ...videoExtensions,
  ...audioExtensions,
  ...documentExtensions,
  ...spreadsheetExtensions,
  ...presentationExtensions,
  ...archiveExtensions,
});

const maxFileSizeBytes = 200 * 1024 * 1024;

String extensionOf(String fileName) {
  final dotIndex = fileName.lastIndexOf('.');
  if (dotIndex <= 0 || dotIndex == fileName.length - 1) return '';
  return fileName.substring(dotIndex + 1).toLowerCase();
}

bool isImageFile(String fileName) =>
    imageExtensions.contains(extensionOf(fileName));

bool isVideoFile(String fileName) =>
    videoExtensions.contains(extensionOf(fileName));

bool isSendableFile(String fileName, int sizeBytes) =>
    sizeBytes <= maxFileSizeBytes &&
    allowedFileExtensions.contains(extensionOf(fileName));

IconData fileIconFor(String fileName) {
  final ext = extensionOf(fileName);
  if (imageExtensions.contains(ext)) return Icons.image_outlined;
  if (videoExtensions.contains(ext)) return Icons.movie_outlined;
  if (audioExtensions.contains(ext)) return Icons.audiotrack;
  if (archiveExtensions.contains(ext)) return Icons.folder_zip_outlined;
  if (ext == 'pdf') return Icons.picture_as_pdf_outlined;
  if (spreadsheetExtensions.contains(ext)) return Icons.table_chart_outlined;
  if (presentationExtensions.contains(ext)) return Icons.slideshow_outlined;
  return Icons.insert_drive_file_outlined;
}
