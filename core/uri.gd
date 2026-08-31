@tool
class_name Uri
extends RefCounted

## Lightweight URI value used by Cherry's GDScript APIs.
##
## This class models ordinary URI components rather than Cherry Navigation
## concepts. Navigation shorthand such as [code]/settings[/code] is canonicalized
## by Navigator before parsing and is intentionally not understood here.
##
## Query and fragment retain their URI delimiters to mirror System.Uri:
## [code]query == "?id=123"[/code] and [code]fragment == "#friends"[/code].
## Percent-encoded component text is preserved; query helper methods decode only
## individual key/value components.

## Exact string supplied to [method parse] / [method try_parse].
var original_string: String = ""

## Lower-cased URI scheme without the trailing colon.
var scheme: String = ""

## Authority text between [code]//[/code] and the first path separator.
var authority: String = ""

## Optional user-info portion of [member authority], without the trailing @.
var user_info: String = ""

## Host portion of [member authority].
var host: String = ""

## Explicit numeric port, or -1 when no port is present.
var port: int = -1

## Escaped URI path component. For hierarchical URIs this normally begins with /.
var path: String = ""

## Alias matching System.Uri.AbsolutePath terminology.
var absolute_path: String:
    get:
        return path

## Raw escaped query including the leading ?, or an empty string.
var query: String = ""

## Raw escaped fragment including the leading #, or an empty string.
var fragment: String = ""

## Whether the source contains an absolute URI scheme.
var is_absolute_uri: bool:
    get:
        return not scheme.is_empty()

var _has_authority := false

## Parses [param value] and reports an error when it is not a valid absolute URI.
##
## Returns null on failure because GDScript does not provide a catchable
## exception model comparable to System.Uri construction.
static func parse(value: String) -> Uri:
    var uri := try_parse(value)
    if uri == null:
        push_error("Invalid URI: %s" % value)
    return uri

## Attempts to parse [param value] as an absolute URI without reporting errors.
static func try_parse(value: String) -> Uri:
    var raw := value.strip_edges()
    if raw.is_empty():
        return null

    var main := raw
    var parsed_fragment := ""
    var fragment_index := main.find("#")
    if fragment_index >= 0:
        parsed_fragment = main.substr(fragment_index)
        main = main.left(fragment_index)

    var parsed_query := ""
    var query_index := main.find("?")
    if query_index >= 0:
        parsed_query = main.substr(query_index)
        main = main.left(query_index)

    var scheme_index := main.find(":")
    if scheme_index <= 0:
        return null

    var parsed_scheme := main.left(scheme_index)
    if not _is_valid_scheme(parsed_scheme):
        return null

    var remainder := main.substr(scheme_index + 1)
    var parsed_authority := ""
    var parsed_path := ""
    var has_authority := remainder.begins_with("//")
    if has_authority:
        var authority_and_path := remainder.substr(2)
        var slash_index := authority_and_path.find("/")
        if slash_index >= 0:
            parsed_authority = authority_and_path.left(slash_index)
            parsed_path = authority_and_path.substr(slash_index)
        else:
            parsed_authority = authority_and_path
    else:
        parsed_path = remainder

    var result := Uri.new()
    result.original_string = raw
    result.scheme = parsed_scheme.to_lower()
    result.authority = parsed_authority
    result.path = parsed_path
    result.query = parsed_query
    result.fragment = parsed_fragment
    result._has_authority = has_authority
    result._parse_authority()
    return result

## Returns the URI prefix through the path, excluding query and fragment.
##
## This is the GDScript analogue of using System.Uri's left path portion. It is
## a general URI operation and does not perform Cherry route normalization.
func get_left_part() -> String:
    if scheme.is_empty():
        return ""
    var result := scheme + ":"
    if _has_authority:
        result += "//" + authority
    result += path
    return result

## Returns the first decoded value for [param name], or [param default_value].
##
## Repeated keys are preserved by [method get_query_values]. A plus sign remains
## a plus sign; this helper performs URI percent-decoding, not HTML form decoding.
func get_query_value(name: String, default_value: String = "") -> String:
    var values := get_query_values(name)
    return values[0] if not values.is_empty() else default_value

## Returns every decoded query value for [param name] in source order.
func get_query_values(name: String) -> Array[String]:
    var result: Array[String] = []
    if query.is_empty():
        return result
    var source := query.substr(1) if query.begins_with("?") else query
    for pair: String in source.split("&", true):
        if pair.is_empty():
            continue
        var equals_index := pair.find("=")
        var raw_name := pair if equals_index < 0 else pair.left(equals_index)
        if raw_name.uri_decode() != name:
            continue
        var raw_value := "" if equals_index < 0 else pair.substr(equals_index + 1)
        result.append(raw_value.uri_decode())
    return result

func _to_string() -> String:
    return original_string

func _parse_authority() -> void:
    user_info = ""
    host = ""
    port = -1
    if authority.is_empty():
        return

    var host_port := authority
    var at_index := host_port.rfind("@")
    if at_index >= 0:
        user_info = host_port.left(at_index)
        host_port = host_port.substr(at_index + 1)

    if host_port.begins_with("["):
        var closing := host_port.find("]")
        if closing < 0:
            host = host_port
            return
        host = host_port.substr(0, closing + 1).to_lower()
        if closing + 1 < host_port.length() and host_port[closing + 1] == ":":
            var port_text := host_port.substr(closing + 2)
            if port_text.is_valid_int():
                port = int(port_text)
        return

    var colon_index := host_port.rfind(":")
    if colon_index > 0 and host_port.find(":") == colon_index:
        var port_text := host_port.substr(colon_index + 1)
        if port_text.is_valid_int():
            host = host_port.left(colon_index).to_lower()
            port = int(port_text)
            return
    host = host_port.to_lower()

static func _is_valid_scheme(value: String) -> bool:
    if value.is_empty():
        return false
    var first := value.unicode_at(0)
    if not _is_ascii_alpha(first):
        return false
    for index: int in range(1, value.length()):
        var code := value.unicode_at(index)
        if _is_ascii_alpha(code) or (code >= 48 and code <= 57) or code == 43 or code == 45 or code == 46:
            continue
        return false
    return true

static func _is_ascii_alpha(code: int) -> bool:
    return (code >= 65 and code <= 90) or (code >= 97 and code <= 122)
