// Oniguruma as vscode-oniguruma exposes it: an OnigScanner over a list of
// patterns, whose findNextMatchSync finds the earliest match of any of them.
// Bound by lib/ide/editor/textmate/oniguruma/onig_native.dart and built by
// hook/build.dart together with Oniguruma (native/oniguruma/onig).
//
// Adapted from vscode-oniguruma 1.7.0
// (716aeaa229e4ae2e3b0057377b55743e9a3e995b): src/onig.cc (MIT, see
// native/oniguruma/LICENSE.txt). Oniguruma is BSD-2-Clause, see
// native/oniguruma/onig/COPYING.
//
// The searches, their options, the per-regex cache and the result are
// onig.cc's. So is what an invalid pattern does, as its published
// WebAssembly (the one VS Code runs) does it rather than as its source reads:
// createOnigScanner reads the failed regex before checking it for NULL, so
// the compiler drops the check, and the scanner is made all the same, with a
// NULL OnigRegExp and a NULL regex_t (read from WebAssembly's zeroed low
// memory) for the pattern:
// - The NULL OnigRegExp never matches. Searching it writes its cache fields
//   to low memory, where a NULL regex_t's num_mem is: the last such search's
//   options, process-wide (failedSearchOption).
// - onig_regset_new takes NULL regex_ts only among themselves (their encoding
//   reads as NULL), and onig.cc ignores its refusal: a scanner with both
//   valid and invalid patterns has no regset, and no match in a string under
//   1000 bytes. One of only invalid patterns has a regset of NULL regex_ts,
//   which matches empty at the start position while failedSearchOption is
//   none, and otherwise has more registers than onig.cc returns.
// - A valid pattern with (?L) (find longest) is refused a regset too.
// baocode_onig_scanner_new reports the first invalid pattern instead of
// keeping a global for getLastOnigError. Oniguruma is initialized once
// explicitly, where onig.cc's first onig_new does it implicitly.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>

#include "oniguruma.h"

#if defined(_WIN32)
#define WIN32_LEAN_AND_MEAN
#include <windows.h>
#define BAOCODE_ONIG_EXPORT __declspec(dllexport)
#else
#include <pthread.h>
#include <time.h>
#define BAOCODE_ONIG_EXPORT __attribute__((visibility("default")))
#endif

#if defined(_WIN32)

static INIT_ONCE initOnce = INIT_ONCE_STATIC_INIT;

static BOOL CALLBACK initializeOniguruma(PINIT_ONCE once, PVOID parameter,
                                         PVOID* context) {
  OnigEncoding encodings[] = {ONIG_ENCODING_UTF8};
  (void)once;
  (void)parameter;
  (void)context;
  onig_initialize(encodings, 1);
  return TRUE;
}

static void ensureInitialized(void) {
  InitOnceExecuteOnce(&initOnce, initializeOniguruma, NULL, NULL);
}

static double nowMilliseconds(void) {
  LARGE_INTEGER frequency, counter;
  QueryPerformanceFrequency(&frequency);
  QueryPerformanceCounter(&counter);
  return (double)counter.QuadPart * 1000.0 / (double)frequency.QuadPart;
}

#else

static pthread_once_t initOnce = PTHREAD_ONCE_INIT;

static void initializeOniguruma(void) {
  OnigEncoding encodings[] = {ONIG_ENCODING_UTF8};
  onig_initialize(encodings, 1);
}

static void ensureInitialized(void) {
  pthread_once(&initOnce, initializeOniguruma);
}

static double nowMilliseconds(void) {
  struct timespec now;
  clock_gettime(CLOCK_MONOTONIC, &now);
  return (double)now.tv_sec * 1000.0 + (double)now.tv_nsec / 1e6;
}

#endif

BAOCODE_ONIG_EXPORT void* baocode_onig_malloc(int64_t count) {
  return malloc(count > 0 ? (size_t)count : 1);
}

BAOCODE_ONIG_EXPORT void baocode_onig_free(void* pointer) { free(pointer); }

static volatile int64_t lastStringId = 0;

// OnigString's `LAST_ID`: an id for each string, so that a regex's cached
// search is only reused on the string it was made on. Process-wide, as
// scanners are.
BAOCODE_ONIG_EXPORT int64_t baocode_onig_next_string_id(void) {
#if defined(_MSC_VER)
  return InterlockedIncrement64(&lastStringId);
#else
  return __atomic_add_fetch(&lastStringId, 1, __ATOMIC_RELAXED);
#endif
}

BAOCODE_ONIG_EXPORT int32_t baocode_onig_version(void) {
  return ONIGURUMA_VERSION_INT;
}

typedef struct OnigRegExp_ {
  unsigned char* strData;
  int strLength;
  regex_t* regex;
  OnigRegion* region;
  int hasGAnchor;
  int64_t lastSearchStrCacheId;
  int lastSearchPosition;
  OnigOptionType lastSearchOnigOption;
  int lastSearchMatched;
} OnigRegExp;

typedef struct BaoCodeOnigScanner_ {
  // NULL when refused one: see the top of the file.
  OnigRegSet* rset;
  // NULL for an invalid pattern.
  OnigRegExp** regexes;
  int count;
  int invalidCount;
  // The match: its register count, then each register's start and end.
  int32_t* result;
  int capacity;
} BaoCodeOnigScanner;

#define MAX_REGIONS 1000

// Returns index, or -1 for none, having put the region in the result.
static int32_t encodeOnigRegion(BaoCodeOnigScanner* scanner, OnigRegion* result,
                                int index) {
  int i;
  if (result == NULL || result->num_regs > MAX_REGIONS ||
      result->num_regs > scanner->capacity) {
    return -1;
  }

  scanner->result[0] = result->num_regs;
  for (i = 0; i < result->num_regs; i++) {
    scanner->result[2 * i + 1] = result->beg[i];
    scanner->result[2 * i + 2] = result->end[i];
  }
  return index;
}

// strData + offset for any offset, as onig.cc's WebAssembly computes it;
// Oniguruma itself rejects a start outside the string.
static const UChar* offsetInto(const UChar* strData, int offset) {
  return (const UChar*)((uintptr_t)strData + (uintptr_t)(intptr_t)offset);
}

// OnigRegExp

static int hasGAnchor(const unsigned char* str, int len) {
  int pos;
  for (pos = 0; pos < len; pos++) {
    if (str[pos] == '\\' && pos + 1 < len) {
      if (str[pos + 1] == 'G') {
        return 1;
      }
    }
  }
  return 0;
}

static OnigRegExp* createOnigRegExp(const unsigned char* data, int length,
                                    int* status, OnigErrorInfo* errorInfo) {
  OnigRegExp* result;
  regex_t* regex;

  *status = onig_new(&regex, data, data + length, ONIG_OPTION_CAPTURE_GROUP,
                     ONIG_ENCODING_UTF8, ONIG_SYNTAX_DEFAULT, errorInfo);

  if (*status != ONIG_NORMAL) {
    return NULL;
  }

  result = (OnigRegExp*)malloc(sizeof(OnigRegExp));
  result->strLength = length;
  result->strData = (unsigned char*)malloc(length > 0 ? length : 1);
  memcpy(result->strData, data, length);
  result->regex = regex;
  result->region = onig_region_new();
  result->hasGAnchor = hasGAnchor(data, length);
  result->lastSearchStrCacheId = 0;
  result->lastSearchPosition = 0;
  result->lastSearchOnigOption = ONIG_OPTION_NONE;
  result->lastSearchMatched = 0;
  return result;
}

static void freeOnigRegExp(OnigRegExp* regex) {
  // regex->regex will be freed separately / as part of the regset
  free(regex->strData);
  onig_region_free(regex->region, 1);
  free(regex);
}

static OnigRegion* _searchOnigRegExp(OnigRegExp* regex,
                                     const unsigned char* strData,
                                     int strLength, int position,
                                     OnigOptionType onigOption) {
  int status;

  status = onig_search(regex->regex, strData, strData + strLength,
                       offsetInto(strData, position), strData + strLength,
                       regex->region, onigOption);

  if (status == ONIG_MISMATCH || status < 0) {
    regex->lastSearchMatched = 0;
    return NULL;
  }

  regex->lastSearchMatched = 1;
  return regex->region;
}

// The options of the last search of an invalid pattern's NULL OnigRegExp:
// see the top of the file.
static volatile OnigOptionType failedSearchOption = ONIG_OPTION_NONE;

static OnigRegion* searchOnigRegExp(OnigRegExp* regex, int64_t strCacheId,
                                    const unsigned char* strData,
                                    int strLength, int position,
                                    OnigOptionType onigOption) {
  if (regex == NULL) {
    failedSearchOption = onigOption;
    return NULL;
  }

  if (regex->hasGAnchor) {
    // Should not use caching, because the regular expression
    // targets the current search position (\G)
    return _searchOnigRegExp(regex, strData, strLength, position, onigOption);
  }

  if (regex->lastSearchStrCacheId == strCacheId &&
      regex->lastSearchOnigOption == onigOption &&
      regex->lastSearchPosition <= position) {
    if (!regex->lastSearchMatched) {
      // last time there was no match
      return NULL;
    }
    if (regex->region->beg[0] >= position) {
      // last time there was a match and it occured after position
      return regex->region;
    }
  }

  regex->lastSearchStrCacheId = strCacheId;
  regex->lastSearchPosition = position;
  regex->lastSearchOnigOption = onigOption;
  return _searchOnigRegExp(regex, strData, strLength, position, onigOption);
}

// OnigScanner

// A scanner over [count] UTF-8 patterns, laid end to end in [patterns]. Puts the index of the first invalid pattern in
// [invalid] (-1 for none) and Oniguruma's message for it in [error]
// (ONIG_MAX_ERROR_MESSAGE_LEN bytes).
BAOCODE_ONIG_EXPORT BaoCodeOnigScanner* baocode_onig_scanner_new(
    const uint8_t* patterns, const int32_t* lengths, int32_t count,
    int32_t* invalid, uint8_t* error) {
  int i;
  int status = ONIG_NORMAL;
  int invalidCount = 0;
  int capacity = 1;
  int64_t offset = 0;
  OnigErrorInfo errorInfo;
  OnigRegExp** regexes;
  regex_t** regs;
  OnigRegSet* rset = NULL;
  BaoCodeOnigScanner* scanner;

  ensureInitialized();
  *invalid = -1;

  regexes =
      (OnigRegExp**)malloc(sizeof(OnigRegExp*) * (count > 0 ? count : 1));
  regs = (regex_t**)malloc(sizeof(regex_t*) * (count > 0 ? count : 1));

  for (i = 0; i < count; i++) {
    memset(&errorInfo, 0, sizeof(errorInfo));
    regexes[i] =
        createOnigRegExp(patterns + offset, lengths[i], &status, &errorInfo);
    offset += lengths[i];
    if (regexes[i] == NULL) {
      // As onig.cc's WebAssembly goes on: see the top of the file.
      if (invalidCount++ == 0) {
        *invalid = i;
        onig_error_code_to_str((UChar*)error, status, &errorInfo);
      }
      regs[i] = NULL;
      continue;
    }
    regs[i] = regexes[i]->regex;
    if (onig_number_of_captures(regs[i]) + 1 > capacity) {
      capacity = onig_number_of_captures(regs[i]) + 1;
    }
  }

  if (invalidCount == 0 && onig_regset_new(&rset, count, regs) != 0) {
    // As onig.cc, which ignores it: a regex with (?L) (find longest) is
    // refused a regset.
    rset = NULL;
  }
  free(regs);

  // A match with more registers is no match (encodeOnigRegion).
  if (capacity > MAX_REGIONS) {
    capacity = MAX_REGIONS;
  }

  scanner = (BaoCodeOnigScanner*)malloc(sizeof(BaoCodeOnigScanner));
  scanner->rset = rset;
  scanner->regexes = regexes;
  scanner->count = count;
  scanner->invalidCount = invalidCount;
  scanner->capacity = capacity;
  scanner->result = (int32_t*)malloc(sizeof(int32_t) * (1 + 2 * capacity));
  return scanner;
}

BAOCODE_ONIG_EXPORT void baocode_onig_scanner_free(BaoCodeOnigScanner* scanner) {
  int i;
  for (i = 0; i < scanner->count; i++) {
    if (scanner->regexes[i] == NULL) continue;
    if (scanner->rset == NULL) {
      // Not in a regset to free it with.
      onig_free(scanner->regexes[i]->regex);
    }
    freeOnigRegExp(scanner->regexes[i]);
  }
  free(scanner->regexes);
  if (scanner->rset != NULL) {
    onig_regset_free(scanner->rset);
  }
  free(scanner->result);
  free(scanner);
}

// Where baocode_onig_find_next puts a match: its register count, then each
// register's UTF-8 start and end (-1 for a group that did not take part).
BAOCODE_ONIG_EXPORT int32_t* baocode_onig_scanner_result(
    BaoCodeOnigScanner* scanner) {
  return scanner->result;
}

// How many registers the result has room for: 1 + 2 * this int32s.
BAOCODE_ONIG_EXPORT int32_t baocode_onig_scanner_capacity(
    BaoCodeOnigScanner* scanner) {
  return scanner->capacity;
}

#define FIND_OPTION_NONE                 0U
#define FIND_OPTION_NOT_BEGIN_STRING     1U
#define FIND_OPTION_NOT_END_STRING       2U
#define FIND_OPTION_NOT_BEGIN_POSITION   4U
#define FIND_OPTION_DEBUG_CALL           8U

static OnigOptionType toOnigOption(int option) {
  OnigOptionType onigOption = ONIG_OPTION_NONE;
  if (option & FIND_OPTION_NOT_BEGIN_STRING) {
    onigOption |= ONIG_OPTION_NOT_BEGIN_STRING;
  }
  if (option & FIND_OPTION_NOT_END_STRING) {
    onigOption |= ONIG_OPTION_NOT_END_STRING;
  }
  if (option & FIND_OPTION_NOT_BEGIN_POSITION) {
    onigOption |= ONIG_OPTION_NOT_BEGIN_POSITION;
  }
  return onigOption;
}

static int32_t findNextOnigScannerMatch(BaoCodeOnigScanner* scanner,
                                        int64_t strCacheId,
                                        const unsigned char* strData,
                                        int strLength, int position,
                                        int option) {
  int bestLocation = 0;
  int bestResultIndex = 0;
  OnigRegion* bestResult = NULL;
  OnigRegion* result;
  int i;
  int location;
  OnigOptionType onigOption = toOnigOption(option);

  if (strLength < 1000) {
    // for short strings, it is better to use the RegSet API, but for longer strings caching pays off
    if (scanner->rset == NULL) {
      // See the top of the file.
      if (scanner->count > 0 && scanner->invalidCount == scanner->count &&
          failedSearchOption == ONIG_OPTION_NONE && position >= 0 &&
          position <= strLength) {
        scanner->result[0] = 1;
        scanner->result[1] = position;
        scanner->result[2] = position;
        return 0;
      }
      return -1;
    }
    bestResultIndex = onig_regset_search(
        scanner->rset, strData, strData + strLength,
        offsetInto(strData, position), strData + strLength,
        ONIG_REGSET_POSITION_LEAD, onigOption, &bestLocation);
    if (bestResultIndex < 0) {
      return -1;
    }
    return encodeOnigRegion(
        scanner, onig_regset_get_region(scanner->rset, bestResultIndex),
        bestResultIndex);
  }

  for (i = 0; i < scanner->count; i++) {
    result = searchOnigRegExp(scanner->regexes[i], strCacheId, strData,
                              strLength, position, onigOption);
    if (result != NULL && result->num_regs > 0) {
      location = result->beg[0];

      if (bestResult == NULL || location < bestLocation) {
        bestLocation = location;
        bestResult = result;
        bestResultIndex = i;
      }

      if (location == position) {
        break;
      }
    }
  }

  if (bestResult == NULL) {
    return -1;
  }

  return encodeOnigRegion(scanner, bestResult, bestResultIndex);
}

static int32_t findNextOnigScannerMatchDbg(BaoCodeOnigScanner* scanner,
                                           int64_t strCacheId,
                                           const unsigned char* strData,
                                           int strLength, int position,
                                           int option) {
  int bestLocation = 0;
  int bestResultIndex = 0;
  OnigRegion* bestResult = NULL;
  OnigRegion* result;
  OnigRegExp* regex;
  int i;
  int location;
  OnigOptionType onigOption = toOnigOption(option);
  double startTime;
  double elapsedTime;

  printf("\n~~~~~~~~~~~~~~~~~~~~\nEntering findNextOnigScannerMatch:%.*s\n",
         strLength, strData);

  for (i = 0; i < scanner->count; i++) {
    regex = scanner->regexes[i];
    printf("- searchOnigRegExp: %.*s\n", regex != NULL ? regex->strLength : 0,
           regex != NULL ? (const char*)regex->strData : "");
    startTime = nowMilliseconds();
    result = searchOnigRegExp(regex, strCacheId, strData, strLength, position,
                              onigOption);
    elapsedTime = nowMilliseconds() - startTime;
    if (result != NULL && result->num_regs > 0) {
      location = result->beg[0];
      printf("|- matched after %.3f ms at byte offset %d\n", elapsedTime,
             location);

      if (bestResult == NULL || location < bestLocation) {
        bestLocation = location;
        bestResult = result;
        bestResultIndex = i;
      }

      if (location == position) {
        break;
      }
    } else {
      printf("|- did not match after %.3f ms\n", elapsedTime);
    }
  }

  printf("Leaving findNextOnigScannerMatch\n\n");
  fflush(stdout);

  if (bestResult == NULL) {
    return -1;
  }

  return encodeOnigRegion(scanner, bestResult, bestResultIndex);
}

// The index of the pattern with the earliest match at or after the UTF-8
// [position] of [strData] (on a tie, the lowest), with the match in the
// result; or -1. [strCacheId] names the string for the per-regex cache; with
// FindOption.DebugCall in [option], each regex's search is logged, as with
// onig.cc's findNextOnigScannerMatchDbg.
BAOCODE_ONIG_EXPORT int32_t baocode_onig_find_next(BaoCodeOnigScanner* scanner,
                                               int64_t strCacheId,
                                               const uint8_t* strData,
                                               int32_t strLength,
                                               int32_t position,
                                               int32_t option) {
  if (option & FIND_OPTION_DEBUG_CALL) {
    return findNextOnigScannerMatchDbg(scanner, strCacheId, strData,
                                       strLength, position, option);
  }
  return findNextOnigScannerMatch(scanner, strCacheId, strData, strLength,
                                  position, option);
}
