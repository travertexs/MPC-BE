#define PACKAGE_VERSION "1.5.0"

#if defined(_M_IX86) || defined(_M_X64)
#define FLAC__HAS_X86INTRIN 1
#endif

#define FLAC__ALIGN_MALLOC_DATA 1
#define FLAC__NO_DLL 1

#ifdef _DEBUG
#define FLAC__OVERFLOW_DETECT 1
#endif
