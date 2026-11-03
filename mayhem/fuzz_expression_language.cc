// Fuzz crown's expression language compiler and VM (src/resource/expression_language.cpp).
#include "core/memory/globals.h"
#include "resource/expression_language.h"
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

using namespace crown;
namespace el = crown::expression_language;

extern "C" int LLVMFuzzerInitialize(int *, char ***)
{
	memory_globals::init();
	return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	char *source = (char *)malloc(size + 1);
	memcpy(source, data, size);
	source[size] = '\0';

	unsigned byte_code[256];
	float stack_data[32];
	const char *variable_names[] = { "a", "b" };
	const float variable_values[] = { 2.0f, 1.5f };
	const char *constant_names[] = { "PI" };
	const float constant_values[] = { 3.14159265359f };

	const unsigned num = el::compile(source
		, 2
		, variable_names
		, 1
		, constant_names
		, constant_values
		, byte_code
		, 256
		);

	if (num <= 256) {
		el::Stack stack(stack_data, 32);
		(void)el::run(byte_code, variable_values, stack);
	}

	free(source);
	return 0;
}
