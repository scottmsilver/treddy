package com.precor.treadmill.di

import com.jakewharton.retrofit2.converter.kotlinx.serialization.asConverterFactory
import com.precor.treadmill.data.preferences.ServerPreferences
import com.precor.treadmill.data.remote.TreadmillApi
import com.precor.treadmill.data.remote.TreadmillWebSocket
import com.precor.treadmill.ui.viewmodel.TreadmillViewModel
import com.precor.treadmill.ui.viewmodel.VoiceViewModel
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.serialization.json.Json
import okhttp3.Interceptor
import okhttp3.MediaType.Companion.toMediaType
import okhttp3.OkHttpClient
import okhttp3.Response
import org.koin.android.ext.koin.androidContext
import org.koin.core.module.dsl.viewModel
import org.koin.dsl.module
import retrofit2.Retrofit
import java.util.concurrent.TimeUnit

val appModule = module {

    single { ServerPreferences(androidContext()) }

    single {
        Json {
            ignoreUnknownKeys = true
            isLenient = true
        }
    }

    single {
        // Use the system default trust manager (validates certificate chains
        // including Tailscale's CA) but relax hostname verification since
        // users may connect via IP address or local hostname where the cert
        // CN won't match.
        OkHttpClient.Builder()
            .hostnameVerifier { _, _ -> true }
            .addInterceptor(DynamicBaseUrlInterceptor(get()))
            .connectTimeout(10, TimeUnit.SECONDS)
            .readTimeout(30, TimeUnit.SECONDS)
            .writeTimeout(30, TimeUnit.SECONDS)
            .build()
    }

    single {
        val json: Json = get()
        Retrofit.Builder()
            .baseUrl("http://placeholder.invalid/")
            .client(get())
            .addConverterFactory(json.asConverterFactory("application/json".toMediaType()))
            .build()
    }

    single { get<Retrofit>().create(TreadmillApi::class.java) }

    single { TreadmillWebSocket(get(), get()) }

    viewModel { TreadmillViewModel(get(), get(), get()) }
    viewModel { VoiceViewModel(get(), get()) }
}

/**
 * Interceptor that replaces the placeholder base URL with the actual server URL
 * from DataStore preferences on each request.
 *
 * Uses a cached @Volatile field updated by a coroutine collector instead of
 * runBlocking on every request, which would block OkHttp dispatcher threads.
 */
private class DynamicBaseUrlInterceptor(
    serverPreferences: ServerPreferences,
) : Interceptor {
    @Volatile
    private var cachedUrl: String = runBlocking { serverPreferences.serverUrl.first() }

    init {
        CoroutineScope(SupervisorJob() + Dispatchers.IO).launch {
            serverPreferences.serverUrl.collect { url ->
                cachedUrl = url
            }
        }
    }

    override fun intercept(chain: Interceptor.Chain): Response {
        val original = chain.request()
        val serverUrl = cachedUrl

        if (serverUrl.isBlank()) {
            return chain.proceed(original)
        }

        val baseUrl = serverUrl.trimEnd('/')
        val newUrl = original.url.toString().replace(
            "http://placeholder.invalid/",
            "$baseUrl/"
        )

        val newRequest = original.newBuilder()
            .url(newUrl)
            .build()

        return chain.proceed(newRequest)
    }
}
