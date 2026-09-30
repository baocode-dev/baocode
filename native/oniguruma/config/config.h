/*
 * Oniguruma's config.h, for every platform hook/build.dart builds
 * native/oniguruma on. Oniguruma's own builds make it by probing the system
 * (configure.ac or src/config.h.cmake.in) or copy src/config.h.windows.in on
 * Windows; this takes the same values from the compiler instead. Only the
 * macros Oniguruma reads are defined. As in vscode-oniguruma's default
 * `./configure`, neither USE_CRNL_AS_LINE_TERMINATOR nor the POSIX API is on.
 */

#ifndef MONAD_ONIG_CONFIG_H
#define MONAD_ONIG_CONFIG_H

#define PACKAGE "onig"
#define PACKAGE_VERSION "6.9.8"
#define VERSION "6.9.8"

#define HAVE_STDINT_H 1
#define HAVE_INTTYPES_H 1
#define HAVE_SYS_TYPES_H 1
#define HAVE_ALLOCA 1

#define SIZEOF_INT 4
#define SIZEOF_LONG_LONG 8

#if defined(_WIN32)

/* src/config.h.windows.in: LLP64. */
#define SIZEOF_LONG 4
#ifdef _WIN64
#define SIZEOF_VOIDP 8
#else
#define SIZEOF_VOIDP 4
#endif

/* CMakeLists.txt: C `inline` only from Visual Studio 2015. */
#if defined(_MSC_VER) && _MSC_VER <= 1800
#define inline __inline
#endif

#else

#define HAVE_ALLOCA_H 1
#define HAVE_SYS_TIME_H 1
#define HAVE_SYS_TIMES_H 1
#define HAVE_UNISTD_H 1

/* GCC and Clang predefine these. */
#define SIZEOF_LONG __SIZEOF_LONG__
#define SIZEOF_VOIDP __SIZEOF_POINTER__

#endif

#endif /* MONAD_ONIG_CONFIG_H */
