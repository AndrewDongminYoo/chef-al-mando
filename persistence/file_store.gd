extends RefCounted

## File access shared by the campaign and settings stores: whole-file reads and writes, replacement
## of a verified temporary file, and the integer check for parsed JSON numbers.
## Test subclasses of the stores override _write_text and _replace_file to inject failures, so these
## stay instance methods.


## Returns the file's text with an empty reason, or the reason "missing" or "read_failed".
func _read_text(target: String) -> Dictionary:
	if not FileAccess.file_exists(target):
		return {"reason": "missing", "text": ""}
	var file := FileAccess.open(target, FileAccess.READ)
	if file == null:
		return {"reason": "read_failed", "text": ""}
	var text := file.get_as_text()
	var read_error := file.get_error()
	file.close()
	if read_error != OK and read_error != ERR_FILE_EOF:
		return {"reason": "read_failed", "text": ""}
	return {"reason": "", "text": text}


func _is_integer(value: Variant) -> bool:
	if value is int:
		return true
	return value is float and is_finite(value) and value == floor(value) and absf(value) <= 9007199254740991.0


func _write_text(target: String, text: String) -> Error:
	var file := FileAccess.open(target, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var result := file.get_error()
	file.close()
	return result


func _replace_file(source: String, target: String) -> Error:
	return DirAccess.rename_absolute(source, target)
