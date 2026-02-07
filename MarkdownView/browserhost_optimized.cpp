#ifndef E_BOUNDS
#define E_BOUNDS                         _HRESULT_TYPEDEF_(0x8000000BL)
#endif

#include <ExDispID.h>
#include <mshtmdid.h>
#include <comutil.h>
#include <shlobj.h>

#include <vector>
#include "browserhost.h"
#include "functions.h"

using namespace Microsoft::WRL;

// Статический shared environment для переиспользования между экземплярами
CComPtr<ICoreWebView2Environment> CBrowserHost::sSharedEnvironment;

CBrowserHost::CBrowserHost() :
	mImagesHidden(false),
	mEventsCookie(0),
	mRefCount(1),
	fSearchHighlightMode(1),
	fStatusBarUnlockTime(0),
	mIsWebView2Initialized(false),
	mZoomFactor(1.0),
	mScrollTop(0)
{
	mLastSearchString.Empty();
	mLastSearchFlags = 0;
}

CBrowserHost::~CBrowserHost()
{
}

void CBrowserHost::Quit()
{
	if (mWebViewController)
	{
		mWebViewController->Close();
		mWebViewController.Release();
	}
	if (mWebView)
	{
		mWebView.Release();
	}

	if(mWebBrowser)
	{
		AtlUnadvise((IUnknown*)mWebBrowser, DIID_DWebBrowserEvents, mEventsCookie);

		mWebBrowser->Stop();
		mWebBrowser->Quit();

		CComQIPtr<IOleObject> ole_object(mWebBrowser);
		if(ole_object)
			ole_object->Close(0);

		if(!(options.flags&OPT_MOZILLA))
			mWebBrowser.Release();
	}
    
	Release();
}

// Вспомогательная функция для настройки WebView2
void SetupWebView2(CBrowserHost* host, ICoreWebView2* webView)
{
	// Register events - минимальные обработчики
	webView->add_DocumentTitleChanged(
		Callback<ICoreWebView2DocumentTitleChangedEventHandler>(
			[host](ICoreWebView2* sender, IUnknown* args) -> HRESULT {
				host->UpdateTitle();
				return S_OK;
			}).Get(), nullptr);

	// Минимальный скрипт для scroll tracking
	webView->AddScriptToExecuteOnDocumentCreated(
		L"window.addEventListener('scroll', () => { window.chrome.webview.postMessage({type: 'scroll', top: window.pageYOffset}); });",
		nullptr);

	webView->add_WebMessageReceived(
		Callback<ICoreWebView2WebMessageReceivedEventHandler>(
			[host](ICoreWebView2* sender, ICoreWebView2WebMessageReceivedEventArgs* args) -> HRESULT {
				LPWSTR message;
				args->get_WebMessageAsJson(&message);
				if (message && wcsstr(message, L"\"top\":")) {
					wchar_t* pos = wcsstr(message, L"\"top\":");
					if (pos) {
						host->mScrollTop = _wtoi(pos + 6);
					}
				}
				CoTaskMemFree(message);
				return S_OK;
			}).Get(), nullptr);

	webView->add_NavigationCompleted(
		Callback<ICoreWebView2NavigationCompletedEventHandler>(
			[host](ICoreWebView2* sender, ICoreWebView2NavigationCompletedEventArgs* args) -> HRESULT {
				if (options.flags & OPT_SAVEPOS)
					host->LoadPosition();
				return S_OK;
			}).Get(), nullptr);

	webView->add_NavigationStarting(
		Callback<ICoreWebView2NavigationStartingEventHandler>(
			[](ICoreWebView2* sender, ICoreWebView2NavigationStartingEventArgs* args) -> HRESULT {
				LPWSTR uri;
				args->get_Uri(&uri);
				std::wstring wUri = uri;
				
				// Если это не наша внутренняя страница, открываем в браузере
				bool isInternal = (wUri.find(L"markdown.internal") != std::wstring::npos) || 
								 (wUri.find(L"data:text/html") == 0) ||
								 (wUri.find(L"about:blank") == 0);

				if (!isInternal) {
					args->put_Cancel(TRUE);
					ShellExecuteW(NULL, L"open", wUri.c_str(), NULL, NULL, SW_SHOWNORMAL);
				}
				
				CoTaskMemFree(uri);
				return S_OK;
			}).Get(), nullptr);

	// Set settings
	CComPtr<ICoreWebView2Settings> settings;
	webView->get_Settings(&settings);
	if (settings) {
		settings->put_IsScriptEnabled(TRUE);
		settings->put_AreDefaultContextMenusEnabled(TRUE);
		settings->put_IsStatusBarEnabled(FALSE);
		
		CComQIPtr<ICoreWebView2Settings2> settings2 = settings;
		if (settings2) {
			settings2->put_UserAgent(L"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36");
		}
	}
}

CLSID CLSID_MozillaBrowser = {0x1339B54C,0x3453,0x11D2,{0x93,0xB9,0x00,0x00,0x00,0x00,0x00,0x00}};

bool CBrowserHost::CreateBrowser(HWND hParent)
{
	mParentWin = hParent;
	AddRef(); // Keep object alive for async callbacks

	// Use AppData\Local for WebView2 user data
	wchar_t appDataPath[MAX_PATH];
	std::wstring wUserDataPath;
	
	if (SUCCEEDED(SHGetFolderPathW(NULL, CSIDL_LOCAL_APPDATA, NULL, 0, appDataPath))) {
		wUserDataPath = std::wstring(appDataPath) + L"\\TotalCommanderMarkdownViewPlugin\\wv2data";
		CreateDirectoryW((std::wstring(appDataPath) + L"\\TotalCommanderMarkdownViewPlugin").c_str(), NULL);
		CreateDirectoryW(wUserDataPath.c_str(), NULL);
	} else {
		wchar_t tempPath[MAX_PATH];
		GetTempPathW(MAX_PATH, tempPath);
		wUserDataPath = std::wstring(tempPath) + L"TotalCommanderMarkdownViewPlugin\\wv2data";
		CreateDirectoryW((std::wstring(tempPath) + L"TotalCommanderMarkdownViewPlugin").c_str(), NULL);
		CreateDirectoryW(wUserDataPath.c_str(), NULL);
	}

	// ОПТИМИЗАЦИЯ: Используем кэшированный Environment если он уже создан
	if (sSharedEnvironment) {
		// Сразу создаем Controller из существующего Environment
		AddRef(); // For the callback
		HRESULT hr = sSharedEnvironment->CreateCoreWebView2Controller(mParentWin,
			Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
				[this](HRESULT result, ICoreWebView2Controller* controller) -> HRESULT {
					if (FAILED(result)) {
						Release();
						return result;
					}

					mWebViewController = controller;
					HRESULT hr_wv = mWebViewController->get_CoreWebView2(&mWebView);
					if (FAILED(hr_wv) || !mWebView) {
						Release();
						return hr_wv;
					}

					// Настройка WebView2
					SetupWebView2(this, mWebView);
					UpdateFolderMapping(mCurrentFolder);
					Resize();

					mIsWebView2Initialized = true;

					// Загружаем pending content
					if (mPendingHTML.length() > 0) {
						mWebView->NavigateToString(mPendingHTML.c_str());
						mPendingHTML.clear();
					}
					else if (mPendingURL.Length() > 0) {
						std::wstring url = (wchar_t*)mPendingURL;
						
						if (url.length() > 2 && url[1] == L':') {
							wchar_t folder[MAX_PATH];
							wcscpy(folder, url.c_str());
							PathRemoveFileSpecW(folder);
							UpdateFolderMapping(folder);
							
							std::wstring filename = PathFindFileNameW(url.c_str());
							url = L"https://markdown.internal/" + filename;
						}
						
						mWebView->Navigate(url.c_str());
						mPendingURL.Empty();
					}

					Release(); // Done with initialization
					return S_OK;
				}).Get());
		
		return SUCCEEDED(hr);
	}

	// Первый запуск - создаем Environment и кэшируем его
	HRESULT hr = CreateCoreWebView2EnvironmentWithOptions(nullptr, wUserDataPath.c_str(), nullptr,
		Callback<ICoreWebView2CreateCoreWebView2EnvironmentCompletedHandler>(
			[this](HRESULT result, ICoreWebView2Environment* env) -> HRESULT {
				if (FAILED(result)) {
					Release();
					return result;
				}

				// Сохраняем Environment для переиспользования
				sSharedEnvironment = env;

				AddRef(); // For the next callback
				HRESULT hr_controller = env->CreateCoreWebView2Controller(mParentWin,
					Callback<ICoreWebView2CreateCoreWebView2ControllerCompletedHandler>(
						[this](HRESULT result, ICoreWebView2Controller* controller) -> HRESULT {
							if (FAILED(result)) {
								Release();
								return result;
							}

							mWebViewController = controller;
							HRESULT hr_wv = mWebViewController->get_CoreWebView2(&mWebView);
							if (FAILED(hr_wv) || !mWebView) {
								Release();
								return hr_wv;
							}

							// Настройка WebView2
							SetupWebView2(this, mWebView);
							UpdateFolderMapping(mCurrentFolder);
							Resize();

							mIsWebView2Initialized = true;

							// Загружаем pending content
							if (mPendingHTML.length() > 0) {
								mWebView->NavigateToString(mPendingHTML.c_str());
								mPendingHTML.clear();
							}
							else if (mPendingURL.Length() > 0) {
								std::wstring url = (wchar_t*)mPendingURL;
								
								if (url.length() > 2 && url[1] == L':') {
									wchar_t folder[MAX_PATH];
									wcscpy(folder, url.c_str());
									PathRemoveFileSpecW(folder);
									UpdateFolderMapping(folder);
									
									std::wstring filename = PathFindFileNameW(url.c_str());
									url = L"https://markdown.internal/" + filename;
								}
								
								mWebView->Navigate(url.c_str());
								mPendingURL.Empty();
							}

							Release(); // Done with initialization
							return S_OK;
						}).Get());
				
				Release(); // Env callback done
				return S_OK;
			}).Get());

	if (FAILED(hr)) {
		Release();
		return false;
	}

	return true;
}
