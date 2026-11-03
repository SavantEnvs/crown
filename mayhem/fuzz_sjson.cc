// Fuzz crown's SJSON parser (src/core/json/sjson.cpp) and every typed accessor
// resource compilers use on it, by walking the parsed tree recursively.
#include "core/containers/array.inl"
#include "core/guid.h"
#include "core/json/json_object.inl"
#include "core/json/sjson.h"
#include "core/memory/globals.h"
#include "core/strings/dynamic_string.inl"
#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>

using namespace crown;

static void ignore_error(const char *, void *)
{
}

static void walk(const char *json, int depth)
{
	if (depth > 8)
		return;

	sjson::clear_error();

	switch (sjson::type(json)) {
	case JsonValueType::NIL:
		break;
	case JsonValueType::BOOL:
		(void)sjson::parse_bool(json);
		break;
	case JsonValueType::NUMBER:
		(void)sjson::parse_int(json);
		(void)sjson::parse_float(json);
		break;
	case JsonValueType::STRING: {
		DynamicString str(default_allocator());
		sjson::parse_string(str, json);
		DynamicString verbatim(default_allocator());
		sjson::parse_verbatim(verbatim, json);
		(void)sjson::parse_string_id(json);
		(void)sjson::parse_resource_name(json);
		(void)sjson::parse_guid(json);
		break;
	}
	case JsonValueType::ARRAY: {
		JsonArray arr(default_allocator());
		sjson::parse_array(arr, json);
		if (sjson::has_error())
			break;
		// The typed accessors index a fixed number of elements and have no length
		// check, as sjson.h documents ([x, y], [x, y, z], ...); call each one only on
		// an array of the shape it documents, as a caller that knows its schema does.
		switch (array::size(arr)) {
		case 2:
			(void)sjson::parse_vector2(json);
			break;
		case 3:
			(void)sjson::parse_vector3(json);
			break;
		case 4:
			(void)sjson::parse_vector4(json);
			(void)sjson::parse_quaternion(json);
			break;
		case 16:
			(void)sjson::parse_matrix4x4(json);
			break;
		}
		sjson::clear_error();
		for (u32 i = 0; i < array::size(arr); ++i)
			walk(arr[i], depth + 1);
		break;
	}
	case JsonValueType::OBJECT: {
		JsonObject obj(default_allocator());
		sjson::parse_object(obj, json);
		if (sjson::has_error())
			break;
		auto cur = json_object::begin(obj);
		auto end = json_object::end(obj);
		for (; cur != end; ++cur) {
			JSON_OBJECT_SKIP_HOLE(obj, cur);
			walk(cur->second, depth + 1);
		}
		break;
	}
	}
}

extern "C" int LLVMFuzzerInitialize(int *, char ***)
{
	memory_globals::init();
	sjson::set_error_callback(ignore_error, NULL);
	return 0;
}

extern "C" int LLVMFuzzerTestOneInput(const uint8_t *data, size_t size)
{
	char *json = (char *)malloc(size + 1);
	memcpy(json, data, size);
	json[size] = '\0';

	int rc = 0;
	sjson::clear_error();
	{
		JsonObject obj(default_allocator());
		sjson::parse(obj, json);
		if (sjson::has_error()) {
			rc = -1;
		} else {
			auto cur = json_object::begin(obj);
			auto end = json_object::end(obj);
			for (; cur != end; ++cur) {
				JSON_OBJECT_SKIP_HOLE(obj, cur);
				walk(cur->second, 0);
			}
		}
	}

	free(json);
	return rc;
}
