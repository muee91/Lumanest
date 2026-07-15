import 'package:luma_nest/src/core/context/environment_controller.dart';
import 'package:luma_nest/src/core/location/location_repository.dart';

bool isPermanentlyDeniedLocationFailure(Object error) {
  if (error is! EnvironmentLoadFailure ||
      error.kind != EnvironmentFailureKind.location) {
    return false;
  }
  final cause = error.cause;
  return cause is LocationRepositoryFailure &&
      cause.kind == LocationFailureKind.permissionDeniedForever;
}
