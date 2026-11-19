-- Starship for cmd through Clink, with a transient prompt. Register this
-- folder once with `clink installscripts <path to .config\clink>` and run
-- `clink set prompt.transient always`.

-- Past prompts collapse to two blank lines and the character module, keeping
-- the prompt's height, as in transient.{zsh,fish,ps1}.
function starship_transient_prompt_func(prompt)
    return "\n\n" .. io.popen("starship module character"
        .. " --keymap=" .. rl.getvariable('keymap')
    ):read("*a")
end

load(io.popen('starship init cmd'):read("*a"))()
