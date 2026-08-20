import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:peero/utils/file_types.dart';

void main() {
  group('extensionOf', () {
    test('lowercases the part after the last dot', () {
      expect(extensionOf('rapport.PDF'), 'pdf');
      expect(extensionOf('archive.tar.gz'), 'gz');
    });

    test('returns empty for names with no usable extension', () {
      expect(extensionOf('README'), '');
      expect(extensionOf('trailing.'), '');
      expect(extensionOf(''), '');
    });

    test('treats a dotfile as having no extension', () {
      expect(extensionOf('.zip'), '');
      expect(isSendableFile('.zip', 10), isFalse);
    });
  });

  group('category predicates', () {
    test('recognise images and videos', () {
      expect(isImageFile('photo.JPG'), isTrue);
      expect(isImageFile('photo.heic'), isTrue);
      expect(isImageFile('clip.mp4'), isFalse);

      expect(isVideoFile('clip.mkv'), isTrue);
      expect(isVideoFile('photo.png'), isFalse);
    });
  });

  group('allowedFileExtensions', () {
    test('is the union of every category, without duplicates', () {
      final expected = {
        ...imageExtensions,
        ...videoExtensions,
        ...audioExtensions,
        ...documentExtensions,
        ...spreadsheetExtensions,
        ...presentationExtensions,
        ...archiveExtensions,
      };
      expect(allowedFileExtensions.toSet(), expected);
      expect(allowedFileExtensions.length, expected.length);
    });

    test('excludes executables and scripts', () {
      for (final ext in ['exe', 'sh', 'bat', 'app', 'dll', 'js', 'py']) {
        expect(allowedFileExtensions, isNot(contains(ext)), reason: ext);
      }
    });

    test('is unmodifiable so no call site can widen the whitelist', () {
      expect(() => allowedFileExtensions.add('exe'), throwsUnsupportedError);
    });
  });

  group('isSendableFile', () {
    test('accepts an allowed type within the size cap', () {
      expect(isSendableFile('rapport.pdf', 1024), isTrue);
      expect(isSendableFile('rapport.pdf', maxFileSizeBytes), isTrue);
    });

    test('refuses a disallowed type', () {
      expect(isSendableFile('malware.exe', 10), isFalse);
      expect(isSendableFile('noextension', 10), isFalse);
    });

    test('refuses an oversized file even of an allowed type', () {
      expect(isSendableFile('film.mp4', maxFileSizeBytes + 1), isFalse);
    });
  });

  group('fileIconFor', () {
    test('maps each category to its own icon', () {
      expect(fileIconFor('photo.png'), Icons.image_outlined);
      expect(fileIconFor('clip.mp4'), Icons.movie_outlined);
      expect(fileIconFor('song.mp3'), Icons.audiotrack);
      expect(fileIconFor('bundle.zip'), Icons.folder_zip_outlined);
      expect(fileIconFor('rapport.pdf'), Icons.picture_as_pdf_outlined);
      expect(fileIconFor('budget.xlsx'), Icons.table_chart_outlined);
      expect(fileIconFor('deck.pptx'), Icons.slideshow_outlined);
    });

    test('falls back to a generic document icon', () {
      expect(fileIconFor('notes.txt'), Icons.insert_drive_file_outlined);
      expect(fileIconFor('mystery'), Icons.insert_drive_file_outlined);
    });
  });
}
