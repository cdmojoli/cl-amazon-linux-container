# Build an Amazon Linux 2023 container image with a Common Lisp implementation

This project aims to create a container image that allows reproducible
compilation of Common Lisp projects into standalone executables for
Amazon Linux 2023.

It relies on Roswell (<https://github.com/roswell/roswell>) to install
various Common Lisp implementations.

SBCL works well; however, the image can experimentally use other
implementations. ECL (--impl ecl) and Clozure CL (--impl ccl-bin)
appear to work but have been minimally tested. Other implementations
may require additional packages that are not included in the image.

The image can be used to run arbitrary Common Lisp programs with its
included implementation. Please note that for this purpose you may
find the image suboptimal due to its large size, which results from
Roswell dependencies for *building* Common Lisp implementations.

The project was inspired by
<https://github.com/y2q-actionman/cl-aws-custom-runtime-test>.

## Building the image with `build-image.sh`

`build-image.sh` is a thin wrapper around `docker build` that supplies sensible
defaults and a few convenience flags.

### Basic usage

```
./build-image.sh --impl sbcl-bin
```

• Builds the image with the latest *binary* SBCL available via Roswell.
• Produces `cl-amazon-linux:sbcl-bin-<SBCL-VERSION>` (for example
  `cl-amazon-linux:sbcl-bin-2.5.5`).

### Selecting an implementation (and version)

```
./build-image.sh --impl sbcl-bin/2.3.7   # specific SBCL binary release
./build-image.sh --impl sbcl-bin         # latest SBCL binary release
./build-image.sh --impl sbcl             # compile SBCL from source
./build-image.sh --impl ecl/24.5.10      # specific ECL version
./build-image.sh --impl ccl-bin          # latest Clozure CL release
```

• A value ending in `-bin` tells Roswell to **download a pre-built binary**.
• Omitting `-bin` makes Roswell **build the implementation from source**, which
  takes longer and pulls in more development packages.

### Customising image name and tag

```
./build-image.sh -n my-lisp -t v1.0 --impl sbcl-bin
```

(If `-t/--tag` is omitted, the script auto-tags the image based on the
implementation and version.)

### Disabling BuildKit

BuildKit is enabled by default for speed and smaller layers. Disable it when
working with older Docker releases:

```
DOCKER_BUILDKIT=0 ./build-image.sh --impl sbcl-bin
```

### Passing extra arguments to `docker build`

Anything after a literal `--` is forwarded verbatim:

```
./build-image.sh --impl sbcl-bin -- --no-cache
```

### Verifying the image

```
docker run --rm cl-amazon-linux:sbcl-bin-2.5.5 \
  ros run --eval '(format t "~A/~A works!~%" (lisp-implementation-type) (lisp-implementation-version))' -q
```
