-- Starship for cmd through Clink, with a transient prompt. Register this
-- folder once with `clink installscripts <path to .config\clink>` and run
-- `clink set prompt.transient always`.

-- Without Starship, init prints nothing: leave cmd's own prompt alone.
local init = io.popen('starship init cmd 2>nul'):read("*a")
if not init or init == "" then
    return
end

-- Past prompts collapse to two blank lines and the character module, keeping
-- the prompt's height, as in transient.{zsh,fish,ps1}.
function starship_transient_prompt_func(prompt)
    return "\n\n" .. io.popen("starship module character"
        .. " --keymap=" .. rl.getvariable('keymap')
    ):read("*a")
end

load(init)()
