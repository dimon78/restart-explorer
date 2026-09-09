try {
    Add-Type -Name User32 -Namespace Win32 -MemberDefinition '
    [DllImport("user32.dll")] public static extern int PostMessage(int hWnd, int Msg, int wParam, int lParam);
    '
    
    # PostMessage не ждет ответа, просто отправляет в очередь
    $result = [Win32.User32]::PostMessage(0xFFFF, 0x0112, 0xF170, 2)
    
    if ($result -ne 0) {
        Write-Output "Display turn off command sent successfully."
    } else {
        Write-Output "Failed to send display turn off command."
    }
} catch {
    Write-Output "Error turning off display: $_"
}