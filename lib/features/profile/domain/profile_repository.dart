import '../../../core/errors/result.dart';
import 'profile.dart';

abstract interface class ProfileRepository {
  Future<Profile?> current(String accountId);
  Stream<Profile?> watch(String accountId);

  /// Creates or updates the profile. Validation failures write nothing.
  Future<Result<Profile>> save(String accountId, ProfileDraft draft);

  /// Records that onboarding finished. Later edits do not undo it.
  Future<Result<void>> completeOnboarding(String accountId);

  /// Re-keys the profile from a device account to its cloud user, queued for
  /// upload. Nothing happens when there is no profile under [fromId].
  Future<Result<void>> moveTo({required String fromId, required String toId});
}
