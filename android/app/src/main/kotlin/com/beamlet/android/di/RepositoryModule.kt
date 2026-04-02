package com.beamlet.android.di

import android.content.Context
import com.beamlet.android.data.api.BeamletApiService
import com.beamlet.android.data.auth.AuthRepository
import com.beamlet.android.data.contacts.ContactRepository
import com.beamlet.android.data.files.FileRepository
import com.google.gson.Gson
import dagger.Module
import dagger.Provides
import dagger.hilt.InstallIn
import dagger.hilt.android.qualifiers.ApplicationContext
import dagger.hilt.components.SingletonComponent
import okhttp3.OkHttpClient
import javax.inject.Singleton

@Module
@InstallIn(SingletonComponent::class)
object RepositoryModule {

    @Provides
    @Singleton
    fun provideAuthRepository(
        @ApplicationContext context: Context,
    ): AuthRepository {
        return AuthRepository(context)
    }

    @Provides
    @Singleton
    fun provideFileRepository(
        api: BeamletApiService,
        authRepository: AuthRepository,
        @ApplicationContext context: Context,
    ): FileRepository {
        return FileRepository(api, authRepository, context)
    }

    @Provides
    @Singleton
    fun provideContactRepository(
        api: BeamletApiService,
        authRepository: AuthRepository,
        okHttpClient: OkHttpClient,
        gson: Gson,
    ): ContactRepository {
        return ContactRepository(api, authRepository, okHttpClient, gson)
    }
}
