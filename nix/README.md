# Nix Integration for Modelio

Reproducible builds, development shells, OCI containers, and smoke tests for
Modelio using [Nix flakes](https://nixos.wiki/wiki/Flakes).

## Table of Contents

- [Quick Start](#quick-start)
- [What This Provides](#what-this-provides)
- [How It Works](#how-it-works)
  - [Source Build (package.nix)](#source-build-packagenix)
  - [Dev Shell (shell.nix)](#dev-shell-shellnix)
  - [Container (container.nix)](#container-containernix)
  - [Smoke Test (test.nix)](#smoke-test-testnix)
- [File Layout](#file-layout)
- [Design Decisions](#design-decisions)
- [Updating the FOD Hash](#updating-the-fod-hash)

## Quick Start

```bash
# Build and run Modelio
nix run

# Build without running
nix build

# Enter a development shell (Maven + JDK 11 + native libs)
nix develop

# Build an OCI container image
nix build .#container

# Run smoke tests
nix flake check
```

## What This Provides

| Flake output        | Description |
|---------------------|-------------|
| `packages.default` / `packages.modelio` | Full source build of Modelio 5.4.1 with desktop entry and wrapper script |
| `packages.container` | Minimal OCI container image (layered, with bash and CA certs) |
| `devShells.default` | Dev shell with Maven, JDK 11, native libs, and auto-generated `toolchains.xml` |
| `checks.default` | xvfb-based smoke test that verifies the built binary starts correctly |

All outputs target `x86_64-linux` only.

## How It Works

The flake (`flake.nix`) delegates to module files in `nix/`:

```
flake.nix
  ├── nix/package.nix   → packages.modelio / packages.default
  ├── nix/shell.nix     → devShells.default
  ├── nix/container.nix → packages.container
  └── nix/test.nix      → checks.default
```

### Source Build (`package.nix`)

The build uses a **two-phase fixed-output derivation (FOD)** approach to work
within Nix's sandboxed, network-less build environment:

1. **`mvnDeps` (FOD)** — runs with network access. Executes
   `mvn install` on `AGGREGATOR/pom.xml` and `mvn package` on `products/pom.xml`,
   caching all Maven, Tycho, and P2 dependencies into `$out/.m2/repository`.
   The result is pinned by a SHA-256 content hash (`outputHash`).

2. **Main derivation** — builds fully offline (`--offline`) using the cached
   repo from step 1. Copies the repo to a writable temp directory (Tycho needs
   to write `.tycholock` files), then runs the same Maven commands.

3. **Install phase** — extracts the product tarball from
   `products/target/products/`, replaces the bundled JRE with a symlink to the
   Nix-provided JDK, and creates a wrapper script that sets:
   - `LD_LIBRARY_PATH` for GTK, X11, WebKit, and other native libraries
   - `JAVA_HOME` pointing to the runtime JDK
   - JVM flags: `-Xms1024m -Xmx4096m`, UTF-8 Python console, WebKit TLS config
   - A `.desktop` entry and icon

### Dev Shell (`shell.nix`)

`mkShell` with Maven and JDK 11 on `PATH`, plus native library dependencies in
`buildInputs`. The `shellHook` auto-generates `~/.m2/toolchains.xml` and prints
build instructions:

```
1. mvn clean install -f AGGREGATOR/pom.xml
2. mvn package -f products/pom.xml -Pproduct.org,platform.linux
   Output: products/target/products/*linux*.tar.gz
```

### Container (`container.nix`)

Uses `dockerTools.buildLayeredImage` to produce an OCI image tagged with the
Modelio version. Contents:

- Modelio package
- `bash`, `coreutils`, CA certificates
- `DISPLAY=:99`, SSL cert path pre-configured
- Volumes at `/workspace` and `/root/.modelio`

Load and run:

```bash
nix build .#container
docker load < result
docker run --rm -e DISPLAY=:0 -v /tmp/.X11-unix:/tmp/.X11-unix modelio:5.4.1
```

### Smoke Test (`test.nix`)

A `writeShellApplication` wrapped in `runCommand` (so it runs as a Nix check).
The test:

1. Verifies the `modelio` binary exists and is executable
2. Confirms the JRE symlink is in place
3. Launches Modelio under `xvfb-run`, waits 15 seconds, and checks the process
   is still alive
4. Kills the process and confirms clean exit

## File Layout

| File | Purpose |
|------|---------|
| `flake.nix` | Flake entry point — wires outputs to `nix/*.nix` modules |
| `flake.lock` | Pinned input revisions (nixpkgs 24.11, flake-utils) |
| `nix/package.nix` | Modelio source build (FOD + main derivation) |
| `nix/shell.nix` | Development shell |
| `nix/container.nix` | OCI container image |
| `nix/test.nix` | Smoke test check |
| `nix/README.md` | This file |

## Design Decisions

### 1. JDK 11 for build, latest JDK for runtime

Tycho 2.2.0 (used by Modelio's build) doesn't recognize execution environments
beyond ~JavaSE-16, so the build must use `jdk11`. The installed application
links to the default Nix `jdk` (latest OpenJDK) for runtime — Java is
backward-compatible for running bytecode compiled with older versions.

### 2. Dual toolchain entries (JavaSE-1.8 + JavaSE-11)

Some OSGi bundles in the Modelio source declare
`Bundle-RequiredExecutionEnvironment: JavaSE-1.8`. Tycho's `useJDK=BREE` mode
demands a matching toolchain entry for each referenced execution environment.
Both entries point to `jdk11`, which can compile Java 8 bytecode via
`--release 8`.

### 3. Dynamic missing-directory creation

Approximately 26 directories referenced in `build.properties` `bin.includes`
fields across the source tree are not tracked by git (empty directories). Rather
than maintaining a static list, a `find`+`grep` script at build time parses
every `build.properties` file and creates any missing directories automatically.

### 4. Writable repo copy for Tycho lock files

The FOD output lives in `/nix/store` and is read-only. Tycho creates
`.tycholock` files inside the Maven repository during resolution. The main
derivation copies the cached repo to `$HOME/.m2/repository` and makes it
writable before building.

### 5. `autoPatchelfHook` + `wrapGAppsHook3`

The Eclipse native launcher (`modelio` binary) needs the NixOS dynamic linker
patched in — `autoPatchelfHook` handles this automatically. GTK/GLib environment
variables are handled by `wrapGAppsHook3`, but `dontWrapGApps = true` is set so
that we control wrapper arguments ourselves via `makeWrapper` +
`gappsWrapperArgs`.

### 6. FOD hash maintenance

The `outputHash` in `mvnDeps` pins the exact set of fetched dependencies. When
upstream dependencies change, this hash must be updated. See below.

## Updating the FOD Hash

When Maven dependencies change (e.g., after bumping a version in a `pom.xml`),
the `outputHash` in `nix/package.nix` must be updated:

1. Set the hash to a placeholder:
   ```nix
   outputHash = lib.fakeHash;
   ```

2. Attempt a build:
   ```bash
   nix build 2>&1
   ```

3. The build will fail with a hash mismatch. Copy the `got:` hash from the
   error message.

4. Replace `lib.fakeHash` with the real hash:
   ```nix
   outputHash = "sha256-XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX=";
   ```

5. Rebuild to confirm:
   ```bash
   nix build
   ```
