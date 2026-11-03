// Known-answer probe over crown's parsers: prints computed values for test.sh to assert.
#include "core/containers/array.inl"
#include "core/guid.h"
#include "core/json/json_object.inl"
#include "core/json/sjson.h"
#include "core/math/types.h"
#include "core/memory/globals.h"
#include "core/strings/dynamic_string.inl"
#include "resource/expression_language.h"
#include <stdio.h>
#include <string.h>

using namespace crown;
namespace el = crown::expression_language;

static f32 eval(const char *expr)
{
	unsigned byte_code[256];
	f32 stack_data[32];
	const char *variable_names[] = { "a", "b" };
	const f32 variable_values[] = { 2.0f, 0.5f };
	el::Stack stack(stack_data, 32);
	el::compile(expr, 2, variable_names, 0, NULL, NULL, byte_code, 256);
	el::run(byte_code, variable_values, stack);
	return stack_data[stack.size - 1];
}

int main()
{
	memory_globals::init();

	JsonObject obj(default_allocator());
	sjson::parse(obj, "name = \"crown\"\nsize = [1 2.5 -3]\nflag = true\ncount = 42");
	printf("keys=%u\n", json_object::size(obj));
	DynamicString name(default_allocator());
	sjson::parse_string(name, obj["name"]);
	printf("name=%s\n", name.c_str());
	printf("count=%d\n", sjson::parse_int(obj["count"]));
	printf("flag=%d\n", (int)sjson::parse_bool(obj["flag"]));
	const Vector3 v = sjson::parse_vector3(obj["size"]);
	printf("size=%.2f,%.2f,%.2f\n", v.x, v.y, v.z);

	Guid guid;
	const bool ok = guid::try_parse(guid, "961f8005-6a7e-4371-9272-8454dd786884");
	char buf[GUID_DEBUG_BUF_LEN];
	printf("guid=%d %s\n", (int)ok, guid::to_debug_string(buf, sizeof(buf), guid));

	printf("expr=%.2f\n", eval("3*(a+1)-b"));
	return 0;
}
