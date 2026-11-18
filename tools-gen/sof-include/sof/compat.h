/* SPDX-License-Identifier: BSD-3-Clause
 *
 * Minimal Linux-type shim so the vendored SOF ABI headers compile with MSVC,
 * both in the kernel driver and in user-mode host tools.
 */
#pragma once

#if defined(_KERNEL_MODE)
typedef unsigned char      uint8_t;
typedef unsigned short     uint16_t;
typedef unsigned int       uint32_t;
typedef unsigned long long uint64_t;
typedef signed char        int8_t;
typedef signed short       int16_t;
typedef signed int         int32_t;
typedef signed long long   int64_t;
#else
#include <stdint.h>
#endif

typedef uint8_t  __u8;
typedef uint16_t __u16;
typedef uint32_t __u32;
typedef uint64_t __u64;
typedef int8_t   __s8;
typedef int16_t  __s16;
typedef int32_t  __s32;
typedef int64_t  __s64;
typedef uint16_t __le16;
typedef uint32_t __le32;
typedef uint64_t __le64;

/* Linux in-kernel spellings used by a few uapi headers */
typedef uint8_t u8;
typedef uint16_t u16;
typedef uint32_t u32;
typedef uint64_t u64;

#ifndef BIT
#define BIT(n) (1U << (n))
#endif
#ifndef GENMASK
#define GENMASK(h, l) ((~0U << (l)) & (~0U >> (31 - (h))))
#endif

/* flexible array members / anonymous unions are MSVC extensions */
#pragma warning(disable : 4200 4201)

/* Linux uapi: a flexible array allowed inside a union. MSVC accepts a
 * zero-length array there (warning 4200, disabled above). */
#ifndef DECLARE_FLEX_ARRAY
#define DECLARE_FLEX_ARRAY(TYPE, NAME) TYPE NAME[0]
#endif
