import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:kokoitta_app/backup_invariants.dart';

BackupInvariantPhoto invariantPhoto(
  String id,
  String path, {
  List<String> metadata = const <String>[],
}) => BackupInvariantPhoto(id: id, path: path, metadataStrings: metadata);

BackupInvariantCheck invariantCheck({
  int tripCount = 0,
  int photoCount = 0,
  List<String> tripIds = const <String>[],
  List<BackupInvariantPhoto> photos = const <BackupInvariantPhoto>[],
}) => BackupInvariantCheck(
  tripCount: tripCount,
  photoCount: photoCount,
  tripIds: tripIds,
  photos: photos,
);

void main() {
  group('checkBackupInvariants', () {
    test('上限ちょうど（10旅行・300写真）は受理する', () {
      final issue = checkBackupInvariants(
        invariantCheck(
          tripCount: backupMaxTrips,
          photoCount: backupMaxPhotos,
          tripIds: List<String>.generate(backupMaxTrips, (i) => 'trip-$i'),
          photos: List<BackupInvariantPhoto>.generate(
            backupMaxPhotos,
            (i) => invariantPhoto('photo-$i', 'photos/trip-0-$i.jpg'),
          ),
        ),
      );
      expect(issue, isNull);
    });

    test('旅行数が上限を超えるとtooManyTrips', () {
      final issue = checkBackupInvariants(
        invariantCheck(
          tripCount: backupMaxTrips + 1,
          tripIds: List<String>.generate(backupMaxTrips + 1, (i) => 'trip-$i'),
        ),
      );
      expect(issue?.violation, BackupInvariantViolation.tooManyTrips);
      expect(issue?.subject, contains('旅行数'));
    });

    test('写真数が上限を超えるとtooManyPhotos', () {
      final issue = checkBackupInvariants(
        invariantCheck(
          photoCount: backupMaxPhotos + 1,
          photos: List<BackupInvariantPhoto>.generate(
            backupMaxPhotos + 1,
            (i) => invariantPhoto('photo-$i', 'photos/trip-0-$i.jpg'),
          ),
        ),
      );
      expect(issue?.violation, BackupInvariantViolation.tooManyPhotos);
      expect(issue?.subject, contains('写真枚数'));
    });

    test('写真IDの重複を拒否する', () {
      final issue = checkBackupInvariants(
        invariantCheck(
          photoCount: 2,
          photos: <BackupInvariantPhoto>[
            invariantPhoto('photo-x', 'photos/trip-0-000.jpg'),
            invariantPhoto('photo-x', 'photos/trip-0-001.jpg'),
          ],
        ),
      );
      expect(issue?.violation, BackupInvariantViolation.duplicatePhotoId);
      expect(issue?.subject, contains('photo-x'));
    });

    test('旅行IDの重複を拒否する', () {
      final issue = checkBackupInvariants(
        invariantCheck(tripCount: 2, tripIds: <String>['trip-x', 'trip-x']),
      );
      expect(issue?.violation, BackupInvariantViolation.duplicateTripId);
      expect(issue?.subject, contains('trip-x'));
    });

    test('写真パスの重複を拒否する', () {
      final issue = checkBackupInvariants(
        invariantCheck(
          photoCount: 2,
          photos: <BackupInvariantPhoto>[
            invariantPhoto('photo-a', 'photos/trip-0-000.jpg'),
            invariantPhoto('photo-b', 'photos/trip-0-000.jpg'),
          ],
        ),
      );
      expect(issue?.violation, BackupInvariantViolation.duplicatePhotoPath);
    });

    test('空の写真ID・旅行IDを拒否する', () {
      final emptyPhotoId = checkBackupInvariants(
        invariantCheck(
          photoCount: 1,
          photos: <BackupInvariantPhoto>[
            invariantPhoto('', 'photos/trip-0-000.jpg'),
          ],
        ),
      );
      expect(emptyPhotoId?.violation, BackupInvariantViolation.invalidPhotoId);

      final emptyTripId = checkBackupInvariants(
        invariantCheck(tripCount: 1, tripIds: <String>['']),
      );
      expect(emptyTripId?.violation, BackupInvariantViolation.invalidTripId);
    });

    test('IDが長さ上限を超えると拒否する', () {
      final longId = 'x' * (backupMaxEntityIdLength + 1);
      final photoId = checkBackupInvariants(
        invariantCheck(
          photoCount: 1,
          photos: <BackupInvariantPhoto>[
            invariantPhoto(longId, 'photos/trip-0-000.jpg'),
          ],
        ),
      );
      expect(photoId?.violation, BackupInvariantViolation.invalidPhotoId);

      final tripId = checkBackupInvariants(
        invariantCheck(tripCount: 1, tripIds: <String>[longId]),
      );
      expect(tripId?.violation, BackupInvariantViolation.invalidTripId);
    });

    test('metadataが上限ちょうどは受理し、超過すると拒否する', () {
      final boundary = checkBackupInvariants(
        invariantCheck(
          photoCount: 1,
          photos: <BackupInvariantPhoto>[
            invariantPhoto(
              'photo-meta',
              'photos/trip-0-000.jpg',
              metadata: <String>['x' * backupMaxMetadataStringLength],
            ),
          ],
        ),
      );
      expect(boundary, isNull);

      final over = checkBackupInvariants(
        invariantCheck(
          photoCount: 1,
          photos: <BackupInvariantPhoto>[
            invariantPhoto(
              'photo-meta',
              'photos/trip-0-000.jpg',
              metadata: <String>['x' * (backupMaxMetadataStringLength + 1)],
            ),
          ],
        ),
      );
      expect(over?.violation, BackupInvariantViolation.metadataTooLong);
    });

    test('最初の違反だけが報告される', () {
      final issue = checkBackupInvariants(
        invariantCheck(
          tripCount: backupMaxTrips + 1,
          photoCount: backupMaxPhotos + 1,
          tripIds: <String>['trip-x', 'trip-x'],
          photos: <BackupInvariantPhoto>[
            invariantPhoto('photo-x', 'photos/trip-0-000.jpg'),
            invariantPhoto('photo-x', 'photos/trip-0-001.jpg'),
          ],
        ),
      );
      expect(issue?.violation, BackupInvariantViolation.tooManyTrips);
    });
  });

  group('canonicalPhotoPath', () {
    test('ドット区切りを正規化して同一キーにする', () {
      final base = Directory.systemTemp.createTempSync('kokoitta-canonical');
      try {
        final plain = canonicalPhotoPath(File('${base.path}/dir/photo.jpg'));
        final dotted = canonicalPhotoPath(File('${base.path}/dir/./photo.jpg'));
        final parent = canonicalPhotoPath(
          File('${base.path}/dir/sub/../photo.jpg'),
        );
        expect(plain, dotted);
        expect(plain, parent);
      } finally {
        if (base.existsSync()) base.deleteSync(recursive: true);
      }
    });

    test('Windowsで区切り文字の違いを正規化する', () {
      if (!Platform.isWindows) return;
      final base = Directory.systemTemp.createTempSync('kokoitta-canonical');
      try {
        final forward = canonicalPhotoPath(File('${base.path}/dir/photo.jpg'));
        final backward = canonicalPhotoPath(
          File('${base.path}\\dir\\photo.jpg'),
        );
        expect(forward, backward);
      } finally {
        if (base.existsSync()) base.deleteSync(recursive: true);
      }
    });

    test('Windowsで大文字小文字の違いを正規化する', () {
      if (!Platform.isWindows) return;
      final base = Directory.systemTemp.createTempSync('kokoitta-canonical');
      try {
        final lower = canonicalPhotoPath(File('${base.path}/dir/photo.jpg'));
        final upper = canonicalPhotoPath(File('${base.path}/dir/Photo.JPG'));
        expect(lower, upper);
      } finally {
        if (base.existsSync()) base.deleteSync(recursive: true);
      }
    });
  });
}
