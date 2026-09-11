/// Sink for non-fatal advisories raised by the client.
///
/// Defaults to printing to stdout. Replace it to route warnings into a logger,
/// or set it to a no-op to silence them.
void Function(String message) sanityWarn = print;
