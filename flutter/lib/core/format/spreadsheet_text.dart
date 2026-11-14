/// A user-supplied text value, safe to open in a spreadsheet.
///
/// A name starting `=`, `+`, `-`, `@`, TAB or CR is a formula to Excel and
/// LibreOffice and would run on open (OWASP spreadsheet injection), so it gets a
/// leading apostrophe: Excel shows the cell as text and hides the mark.
///
/// Shared by the barcode-list CSV (Phase 4) and the catalogue workbook (Phase 3),
/// because both hand user text to the same two programs.
String spreadsheetSafeText(String value) =>
    value.isNotEmpty && '=+-@\t\r'.contains(value[0]) ? "'$value" : value;

/// The value behind [spreadsheetSafeText]'s mark, brought back on import.
///
/// The same character set decides what is stripped, for the same reason it
/// decides what is added: an apostrophe in front of anything else is the user's
/// own typing and stays. A value that genuinely begins `'` and then `=`, `+`,
/// `-`, `@`, TAB or CR cannot be told apart from an escaped one in the file, and
/// reads back as the escaped form.
String spreadsheetLiteralText(String value) =>
    value.length > 1 && value[0] == "'" && '=+-@\t\r'.contains(value[1])
    ? value.substring(1)
    : value;
