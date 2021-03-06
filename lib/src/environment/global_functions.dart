part of environment.less;

///
/// Resolves null as false.
///
bool isTrue(bool value) => value != null ? value : false;

///
/// Resolves null as empty. Return false if null.
/// Supports String, List, Map.
///
bool isNotEmpty(value){
  if (value is String) return value.isNotEmpty;
  if (value is List) return value.isNotEmpty;
  if (value is Map) return value.isNotEmpty;
  return false; //if value is null
}

///
/// if [value] is null return default.
///
getValueOrDefault(value, defaultValue) {
  if (value == null) {
    return defaultValue;
  } else {
    return value;
  }
}

///
/// -[value] num. Considers null value.
///
negate(num value) {
  return (value == null) ? null : -value;
}

///
/// Convert n to String, without decimal .0 if possible
/// if n == 0.1 returns '0.1'
/// if n == 0.0 returns '0'
///
String numToString(num n) {
  int i = n.toInt();
  return (n == i) ? i.toString() : n.toString();
}