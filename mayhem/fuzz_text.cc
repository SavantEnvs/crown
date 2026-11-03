// Fuzz crown's path, glob, hex, GUID, UTF-8 and command-line helpers on untrusted strings.
// path::has_trailing_separator() and path::reduce() are left out: both read before the buffer on an
// empty string (mayhem/fuzz_text/known-findings/). The input is split at its first NUL byte into two strings (e.g. pattern/subject).
#include "core/command_line.h"
#include "core/filesystem/path.h"
#include "core/guid.h"
#include "core/memory/globals.h"
#include "core/strings/dynamic_string.inl"
#include "core/strings/string.h"
#include "core/strings/utf8.h"
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

using namespace crown;

extern "C" int LLVMFuzzerInitialize(int *, char ***)
{
	memory_globals::init();
	return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	const void *nul = memchr(data, 0, size);
	const size_t len_a = nul ? (size_t)((const uint8_t *)nul - data) : size;
	const size_t len_b = nul ? size - len_a - 1 : 0;

	char *a = (char *)malloc(len_a + 1);
	char *b = (char *)malloc(len_b + 1);
	memcpy(a, data, len_a);
	a[len_a] = '\0';
	memcpy(b, nul ? data + len_a + 1 : data, len_b);
	b[len_b] = '\0';

	{
		(void)path::is_absolute(a);
		(void)path::is_relative(a);
		(void)path::is_root(a);
		(void)path::is_within_root(a);
		(void)path::basename(a);
		(void)path::extension(a);
		(void)path::parent_dir(a);
		(void)path::is_valid_basename(a);

		DynamicString joined(default_allocator());
		path::join(joined, a, b);
	}
	{
		(void)wildcmp(a, b);
		s64 val;
		(void)from_hex(val, a);
	}
	{
		Guid guid;
		(void)guid::try_parse(guid, a);
	}
	{
		u32 state = 0;
		u32 codepoint = 0;
		for (size_t i = 0; i < len_a; ++i)
			(void)utf8::decode(&state, &codepoint, (uint8_t)a[i]);
	}
	{
		const char *argv[16];
		int argc = 0;
		argv[argc++] = "crown";
		for (char *p = b; *p && argc < 16;) {
			argv[argc++] = p;
			while (*p && *p != ' ')
				++p;
			if (*p)
				*p++ = '\0';
		}
		CommandLine cl(argc, argv);
		(void)cl.has_option("help", 'h');
		(void)cl.get_parameter(0, "source-dir", 's');
	}

	free(a);
	free(b);
	return 0;
}
