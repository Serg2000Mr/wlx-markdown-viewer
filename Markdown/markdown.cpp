#define MAKEDLL
#include "markdown.h"
#include <windows.h>
#include <shlwapi.h>
#include <mutex>
#include <vector>

#pragma comment(lib, "Shlwapi.lib")

typedef char* (__stdcall *PConvertMarkdownToHtml)(const char*, const char*, const char*);
typedef void (__stdcall *PFreeHtmlBuffer)(char*);

// Helper to get current DLL handle
HMODULE GetCurrentModule() {
    HMODULE hModule = NULL;
    GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS | GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
        (LPCWSTR)GetCurrentModule, &hModule);
    return hModule;
}

Markdown::Markdown() {}
Markdown::~Markdown() {}

namespace {
	std::once_flag gEngineInitOnce;
	HMODULE gEngineLib = NULL;
	PConvertMarkdownToHtml gConvertFunc = nullptr;
	PFreeHtmlBuffer gFreeFunc = nullptr;
	std::string gInitErrorHtml;

	void InitEngine()
	{
		wchar_t dllPath[MAX_PATH];
		HMODULE hCurrentDll = GetCurrentModule();
		GetModuleFileNameW(hCurrentDll, dllPath, MAX_PATH);
		PathRemoveFileSpecW(dllPath);

#ifdef _WIN64
		PathAppendW(dllPath, L"MarkdigNative-x64.dll");
		const char* dllName = "MarkdigNative-x64.dll";
#else
		PathAppendW(dllPath, L"MarkdigNative-x86.dll");
		const char* dllName = "MarkdigNative-x86.dll";
#endif

		gEngineLib = LoadLibraryW(dllPath);
		if (!gEngineLib) {
			gEngineLib = LoadLibraryA(dllName);
		}

		if (!gEngineLib) {
			gInitErrorHtml = "<html><body><h1>Error</h1><p>Could not load MarkdigNative DLL.</p></body></html>";
			return;
		}

		gConvertFunc = (PConvertMarkdownToHtml)GetProcAddress(gEngineLib, "ConvertMarkdownToHtml");
		gFreeFunc = (PFreeHtmlBuffer)GetProcAddress(gEngineLib, "FreeHtmlBuffer");
		if (!gConvertFunc || !gFreeFunc) {
			gInitErrorHtml = "<html><body><h1>Error</h1><p>Could not find functions in MarkdigNative DLL</p></body></html>";
		}
	}

	struct EngineShutdown
	{
		~EngineShutdown()
		{
			if (gEngineLib) {
				FreeLibrary(gEngineLib);
				gEngineLib = NULL;
			}
		}
	};

	EngineShutdown gEngineShutdown;
}

std::string __stdcall Markdown::ConvertToHtmlAscii(
    std::string filename,
    std::string cssFile,
    std::string extensions
) {
	std::call_once(gEngineInitOnce, InitEngine);

	if (!gConvertFunc || !gFreeFunc) {
		return gInitErrorHtml.empty()
			? "<html><body><h1>Error</h1><p>MarkdigNative engine not initialized.</p></body></html>"
			: gInitErrorHtml;
	}

	char* resultPtr = gConvertFunc(filename.c_str(), cssFile.c_str(), extensions.c_str());
	std::string result = resultPtr ? resultPtr : "";

	if (resultPtr) {
		gFreeFunc(resultPtr);
	}

	return result;
}
