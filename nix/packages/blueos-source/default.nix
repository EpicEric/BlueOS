# The BlueOS version metadata, shared by blueos-core and blueos-frontend. The
# source is the repository itself; this records the values that are not
# properties of the commit.
{ self }:
let
  stamp = self.lastModifiedDate or "";
  slice = builtins.substring;
in
{
  # A literal so the version is readable from the closure, not only from git. A
  # flake cannot see its own tags, so this cannot be derived from `git
  # describe`. Bump it as part of cutting a release.
  version = "1.5.0-dev";

  # Reported to Sentry and to the version chooser. `dev` keeps these builds out
  # of Sentry, which only accepts a `<x.y.z>-<commits>-g<hash>` describe string.
  # Available options:
  # - stable
  # - beta
  # - dev
  channel = "dev";

  src = self.outPath;

  # `rev` is absent when the input is a dirty checkout, which is what a `path:`
  # override of a working tree looks like.
  rev = self.rev or (self.dirtyRev or "unknown");

  # The commit's date, in the format the frontend shows as "Build:". Derived
  # from the source rather than the clock: the wall clock would make every build
  # a different store path.
  date = if builtins.stringLength stamp >= 8 then "${slice 0 4 stamp}-${slice 4 2 stamp}-${slice 6 2 stamp}" else "unknown";
}
