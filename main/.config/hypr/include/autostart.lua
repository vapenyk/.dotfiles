hl.on("hyprland.start", function()
    hl.exec_cmd("uwsm app -t service -u mshell.service -p Restart=on-failure -- qs -dn -c mshell")
    hl.exec_cmd("uwsm app -t service -u vicinae-uwsm.service -p Restart=on-failure -- vicinae server")
end)
