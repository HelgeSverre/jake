package com.jakefile.intellij

import com.intellij.openapi.application.PathManager
import org.jetbrains.plugins.textmate.api.TextMateBundleProvider
import java.nio.file.Files
import java.nio.file.Path

class JakeTextMateBundleProvider : TextMateBundleProvider {
    override fun getBundles(): List<TextMateBundleProvider.PluginBundle> {
        return try {
            val tmpDir = Files.createTempDirectory(
                Path.of(PathManager.getTempPath()), "textmate-jake"
            )

            val filesToCopy = listOf(
                "package.json",
                "language-configuration.json",
                "syntaxes/jake.tmLanguage.json"
            )

            for (file in filesToCopy) {
                val resource = javaClass.classLoader.getResource("textmate/jake-bundle/$file")
                if (resource != null) {
                    val target = tmpDir.resolve(file)
                    Files.createDirectories(target.parent)
                    resource.openStream().use { input ->
                        Files.copy(input, target)
                    }
                }
            }

            listOf(TextMateBundleProvider.PluginBundle("Jakefile", tmpDir))
        } catch (e: Exception) {
            emptyList()
        }
    }
}
