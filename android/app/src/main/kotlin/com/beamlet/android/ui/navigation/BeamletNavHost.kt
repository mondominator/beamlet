package com.beamlet.android.ui.navigation

import androidx.compose.foundation.layout.padding
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.Inbox
import androidx.compose.material.icons.filled.Send
import androidx.compose.material.icons.filled.Settings
import androidx.compose.material3.Icon
import androidx.compose.material3.NavigationBar
import androidx.compose.material3.NavigationBarItem
import androidx.compose.material3.Scaffold
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.navigation.NavDestination.Companion.hierarchy
import androidx.navigation.NavGraph.Companion.findStartDestination
import androidx.navigation.NavHostController
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.currentBackStackEntryAsState
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import com.beamlet.android.data.auth.AuthRepository
import com.beamlet.android.data.contacts.ContactRepository
import com.beamlet.android.data.files.FileRepository
import com.beamlet.android.scanner.QrScannerScreen
import com.beamlet.android.ui.inbox.ImageViewerScreen
import com.beamlet.android.ui.inbox.InboxScreen
import com.beamlet.android.ui.send.SendScreen
import com.beamlet.android.ui.settings.AddContactScreen
import com.beamlet.android.ui.settings.ContactsScreen
import com.beamlet.android.ui.settings.SettingsScreen
import com.beamlet.android.ui.setup.SetupScreen
import com.beamlet.android.ui.setup.SetupViewModel
import com.google.gson.Gson

object Routes {
    const val SETUP = "setup"
    const val MAIN = "main"
    const val INBOX = "inbox"
    const val SEND = "send"
    const val SETTINGS = "settings"
    const val QR_SCANNER = "qr_scanner"
    const val IMAGE_VIEWER = "image_viewer/{fileId}"
    const val CONTACTS = "contacts"
    const val ADD_CONTACT = "add_contact"

    fun imageViewer(fileId: String) = "image_viewer/$fileId"
}

sealed class BottomNavItem(
    val route: String,
    val icon: ImageVector,
    val label: String,
) {
    data object Inbox : BottomNavItem(Routes.INBOX, Icons.Default.Inbox, "Inbox")
    data object Send : BottomNavItem(Routes.SEND, Icons.Default.Send, "Send")
    data object Settings : BottomNavItem(Routes.SETTINGS, Icons.Default.Settings, "Settings")
}

private val bottomNavItems = listOf(
    BottomNavItem.Inbox,
    BottomNavItem.Send,
    BottomNavItem.Settings,
)

@Composable
fun BeamletNavHost(
    isAuthenticated: Boolean,
    fileRepository: FileRepository,
    authRepository: AuthRepository,
    contactRepository: ContactRepository,
    gson: Gson,
    pendingFileId: String?,
    onPendingFileHandled: () -> Unit,
    setupViewModel: SetupViewModel,
) {
    val navController = rememberNavController()

    NavHost(
        navController = navController,
        startDestination = if (isAuthenticated) Routes.MAIN else Routes.SETUP,
    ) {
        composable(Routes.SETUP) {
            SetupScreen(
                onNavigateToScanner = { navController.navigate(Routes.QR_SCANNER) },
                viewModel = setupViewModel,
            )
        }

        composable(Routes.QR_SCANNER) {
            QrScannerScreen(
                onBack = { navController.popBackStack() },
                onScanned = { value ->
                    navController.popBackStack()
                    setupViewModel.handleQrScan(value)
                },
            )
        }

        composable(Routes.MAIN) {
            MainScreenWithBottomNav(
                navController = navController,
                fileRepository = fileRepository,
                authRepository = authRepository,
                contactRepository = contactRepository,
                gson = gson,
                pendingFileId = pendingFileId,
                onPendingFileHandled = onPendingFileHandled,
            )
        }

        composable(
            route = Routes.IMAGE_VIEWER,
            arguments = listOf(navArgument("fileId") { type = NavType.StringType }),
        ) { backStackEntry ->
            val fileId = backStackEntry.arguments?.getString("fileId") ?: return@composable
            ImageViewerScreen(
                fileId = fileId,
                fileRepository = fileRepository,
                onDismiss = { navController.popBackStack() },
            )
        }

        composable(Routes.CONTACTS) {
            ContactsScreen(onBack = { navController.popBackStack() })
        }

        composable(Routes.ADD_CONTACT) {
            AddContactScreen(
                authRepository = authRepository,
                contactRepository = contactRepository,
                gson = gson,
                onBack = { navController.popBackStack() },
            )
        }
    }
}

@Composable
private fun MainScreenWithBottomNav(
    navController: NavHostController,
    fileRepository: FileRepository,
    authRepository: AuthRepository,
    contactRepository: ContactRepository,
    gson: Gson,
    pendingFileId: String?,
    onPendingFileHandled: () -> Unit,
) {
    val innerNavController = rememberNavController()

    Scaffold(
        bottomBar = {
            NavigationBar {
                val navBackStackEntry by innerNavController.currentBackStackEntryAsState()
                val currentDestination = navBackStackEntry?.destination

                bottomNavItems.forEach { item ->
                    NavigationBarItem(
                        icon = { Icon(item.icon, contentDescription = item.label) },
                        label = { Text(item.label) },
                        selected = currentDestination?.hierarchy?.any { it.route == item.route } == true,
                        onClick = {
                            innerNavController.navigate(item.route) {
                                popUpTo(innerNavController.graph.findStartDestination().id) {
                                    saveState = true
                                }
                                launchSingleTop = true
                                restoreState = true
                            }
                        },
                    )
                }
            }
        },
    ) { innerPadding ->
        NavHost(
            navController = innerNavController,
            startDestination = Routes.SEND, // Default to Send tab like iOS
            modifier = Modifier.padding(innerPadding),
        ) {
            composable(Routes.INBOX) {
                InboxScreen(
                    onFileClick = { file ->
                        // For non-image files, handle inline (links open browser, text copies)
                    },
                    onImageClick = { fileId ->
                        navController.navigate(Routes.imageViewer(fileId))
                    },
                )
            }

            composable(Routes.SEND) {
                SendScreen()
            }

            composable(Routes.SETTINGS) {
                SettingsScreen(
                    onNavigateToContacts = { navController.navigate(Routes.CONTACTS) },
                    onNavigateToAddContact = { navController.navigate(Routes.ADD_CONTACT) },
                    onNavigateToScanner = { navController.navigate(Routes.QR_SCANNER) },
                )
            }
        }
    }

    // Handle pending file from notification tap
    if (pendingFileId != null) {
        innerNavController.navigate(Routes.INBOX) {
            popUpTo(innerNavController.graph.findStartDestination().id) {
                saveState = true
            }
            launchSingleTop = true
        }
        onPendingFileHandled()
    }
}
