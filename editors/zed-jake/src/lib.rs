use zed_extension_api::{
    self as zed, SlashCommand, SlashCommandArgumentCompletion, SlashCommandOutput,
    SlashCommandOutputSection, Worktree,
};

struct JakeExtension;

impl zed::Extension for JakeExtension {
    fn new() -> Self {
        JakeExtension
    }

    fn complete_slash_command_argument(
        &self,
        command: SlashCommand,
        _args: Vec<String>,
    ) -> Result<Vec<SlashCommandArgumentCompletion>, String> {
        match command.name.as_str() {
            "jake" => {
                // TODO: In future, read Jakefile and parse recipe names for autocomplete
                // For now, return empty (user types recipe name manually)
                Ok(vec![])
            }
            _ => Ok(vec![]),
        }
    }

    fn run_slash_command(
        &self,
        command: SlashCommand,
        args: Vec<String>,
        _worktree: Option<&Worktree>,
    ) -> Result<SlashCommandOutput, String> {
        match command.name.as_str() {
            "jake" => {
                let recipe = args.first().ok_or("Please specify a recipe name")?;

                let text = format!("jake {}", recipe);
                Ok(SlashCommandOutput {
                    sections: vec![SlashCommandOutputSection {
                        range: (0..text.len()).into(),
                        label: format!("Run: jake {}", recipe),
                    }],
                    text,
                })
            }
            _ => Err(format!("Unknown command: {}", command.name)),
        }
    }
}

zed::register_extension!(JakeExtension);
