package org.merlos.openme

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.activity.viewModels
import androidx.compose.runtime.Composable
import androidx.navigation.NavType
import androidx.navigation.compose.NavHost
import androidx.navigation.compose.composable
import androidx.navigation.compose.rememberNavController
import androidx.navigation.navArgument
import org.merlos.openme.ui.ProfileViewModel
import org.merlos.openme.ui.screens.ImportProfileScreen
import org.merlos.openme.ui.screens.ProfileDetailScreen
import org.merlos.openme.ui.screens.ProfileListScreen
import org.merlos.openme.ui.theme.OpenMeTheme

// Navigation route constants
private const val ROUTE_LIST   = "list"
private const val ROUTE_DETAIL = "detail/{profileName}"
private const val ROUTE_IMPORT = "import/{startOnQr}"

class MainActivity : ComponentActivity() {

    private val viewModel: ProfileViewModel by viewModels()

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        setContent {
            OpenMeTheme {
                OpenMeApp(viewModel)
            }
        }
    }
}

@Composable
fun OpenMeApp(viewModel: ProfileViewModel) {
    val navController = rememberNavController()

    NavHost(navController = navController, startDestination = ROUTE_LIST) {

        // Profile list
        composable(ROUTE_LIST) {
            ProfileListScreen(
                viewModel = viewModel,
                onProfileClick = { name ->
                    navController.navigate("detail/$name")
                },
                onImportClick = { startOnQr ->
                    navController.navigate("import/$startOnQr")
                },
            )
        }

        // Profile detail / edit
        composable(
            route = ROUTE_DETAIL,
            arguments = listOf(navArgument("profileName") { type = NavType.StringType }),
        ) { backStackEntry ->
            val name = backStackEntry.arguments?.getString("profileName") ?: return@composable
            ProfileDetailScreen(
                profileName = name,
                viewModel = viewModel,
                onBack = { navController.popBackStack() },
                onDeleted = { navController.popBackStack() },
            )
        }

        // Import (YAML or QR)
        composable(
            route = ROUTE_IMPORT,
            arguments = listOf(navArgument("startOnQr") { type = NavType.BoolType }),
        ) { backStackEntry ->
            val startOnQr = backStackEntry.arguments?.getBoolean("startOnQr") ?: false
            ImportProfileScreen(
                viewModel = viewModel,
                startOnQrTab = startOnQr,
                onBack = { navController.popBackStack() },
                onDone = { navController.popBackStack() },
            )
        }
    }
}
