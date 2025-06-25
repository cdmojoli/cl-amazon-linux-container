FROM amazonlinux:2023

# Only SBCL was well tested. Preliminary tests indicate ECL and
# Clozure CL work too.
#
# CL_IMPLEMENTATION="sbcl-bin/MAJOR.MINOR.PATCH" for specific version, or
# CL_IMPLEMENTATION="sbcl-bin" for current latest version
#
ARG CL_IMPLEMENTATION="sbcl-bin"

ENV LANG=C.UTF-8 \
    LC_ALL=C.UTF-8

WORKDIR /root

RUN \
#
# AL2023 packages
#
    echo -e "***\n*** Installing AL2023 Development Tools." \
# The whole group is an overkill, but it's simple and works.
    && dnf -y group install "Development Tools" \
    && echo -e "***\n*** Installing additional Amazon Linux 2023 packages." \
    && dnf install -y \
    glibc-common \
    glibc-langpack-en \
    libcurl-devel \
    openssl \
    openssl-devel \
    patchelf \
    && dnf clean all \
#
# Roswell
#
    && echo -e "***\n*** Cloning, building and installing Roswell (release)" \
    && git clone -b release https://github.com/roswell/roswell.git \
    && ( cd roswell ; \
    sh bootstrap ; \
    ./configure ; \
    make -j$(nproc); \
    make install ) \
    && rm -rf roswell \
#
# Install Common Lisp implementation. This also installs Quicklisp and
# creates the local-projects directory.
#
    && ros install $CL_IMPLEMENTATION \
    && ros run --eval "(format t \"***~%*** Common Lisp is working.~%\")" -q \
#
# Here we could extend the base with additional quicklisp systems.
#
    && ros run \
    --eval "(format t \"***~%*** Cleaning up Quicklisp distributions.~%\")" \
    --eval "(mapc #'ql-dist:clean (ql-dist:all-dists))" \
    -q \
    && echo -e "***\n*** FINISHED\n***"
