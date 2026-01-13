"utility functions"

# Define the list of reserved characters and their percent-encoded values
_reserved_chars = [
    # To avoid double-escaping, percent must be handled before any other replacements.
    ("%", "%25"),
    #
    (" ", "%20"),
    ("!", "%21"),
    ('"', "%22"),
    ("#", "%23"),
    ("$", "%24"),
    ("&", "%26"),
    ("'", "%27"),
    ("(", "%28"),
    (")", "%29"),
    ("*", "%2A"),
    ("+", "%2B"),
    (",", "%2C"),
    ("/", "%2F"),
    (":", "%3A"),
    (";", "%3B"),
    ("<", "%3C"),
    ("=", "%3D"),
    (">", "%3E"),
    ("?", "%3F"),
    ("@", "%40"),
    ("[", "%5B"),
    ("\\", "%5C"),
    ("]", "%5D"),
    ("^", "%5E"),
    ("`", "%60"),
    ("{", "%7B"),
    ("|", "%7C"),
    ("}", "%7D"),
    ("~", "%7E"),
]

def _url_escape(url):
    """Replace reserved characters with their percent-encoded values"""
    for char, encoded_value in _reserved_chars:
        url = url.replace(char, encoded_value)

    return url

def _repo_url(url, arch):
    """Returns the base url for a given apk url

    For example, given `https://dl-cdn.alpinelinux.org/alpine/edge/main/x86_64/APKINDEX.tar.gz`
    it returns `https://dl-cdn.alpinelinux.org/alpine/edge/main`

    Args:
        url: full url
        arch: arch string
    Returns:
        base url for the url
    """
    arch_index = url.find("{}/".format(arch))
    if arch_index != -1:
        return url[0:arch_index - 1]
    return url

def _sanitize_string(string):
    """Sanitizes a string to be a valid workspace name

    workspace names may contain only A-Z, a-z, 0-9, '-', '_' and '.'

    Args:
        string: unsanitized workspace string
    Returns:
        a valid workspace string
    """

    result = ""
    for i in range(0, len(string)):
        c = string[i]
        if c == "@" and (not result or result[-1] == "_"):
            result += "at"
        if not c.isalnum() and c != "-" and c != "_" and c != ".":
            c = "_"
        result += c
    return result

def _parse_lock(content):
    return json.decode(content)

util = struct(
    parse_lock = _parse_lock,
    sanitize_string = _sanitize_string,
    repo_url = _repo_url,
    url_escape = _url_escape,
)
