#!/usr/bin/awk -f
BEGIN {
  # Use UTC timestamps for consistency
  ENVIRON["TZ"] = "UTC"
}
{
  # ISO 8601 UTC timestamp + original line
  printf "%s %s\n", strftime("%Y-%m-%dT%H:%M:%SZ"), $0
  fflush()
}
