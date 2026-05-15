Add-Type -AssemblyName PresentationFramework
Add-Type -AssemblyName PresentationCore

# Conf
$DeadlineHours = 8
$TaskName      = "Win11UpgradeReboot"
$LogFile       = "C:\Windows\Temp\Win11UpgradeReboot.log"
$Deadline      = (Get-Date).AddHours($DeadlineHours)
$TotalSeconds  = $DeadlineHours * 3600

Function Log($msg) {
    Add-Content -Path $LogFile -Value "$(Get-Date -Format 'yyyy-MM-dd HH:mm:ss') - $msg"
}

Log "Reboot UI started. Deadline: $Deadline"

# Task scheduler
Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue

$Action    = New-ScheduledTaskAction -Execute "shutdown.exe" `
                 -Argument "/r /t 30 /c `"Restarting to finish Windows 11 upgrade.`""

$Trigger   = New-ScheduledTaskTrigger -Once -At $Deadline

$Settings  = New-ScheduledTaskSettingsSet `
                 -ExecutionTimeLimit ([TimeSpan]::FromMinutes(5))
$Settings.DisallowStartIfOnBatteries = $false
$Settings.StopIfGoingOnBatteries     = $false

$Principal = New-ScheduledTaskPrincipal -UserId "SYSTEM" -RunLevel Highest

Register-ScheduledTask -TaskName $TaskName `
    -Action $Action -Trigger $Trigger `
    -Settings $Settings -Principal $Principal -Force | Out-Null

Log "Scheduled task '$TaskName' created for $Deadline."

Function CancelScheduledTask {
    Unregister-ScheduledTask -TaskName $TaskName -Confirm:$false -ErrorAction SilentlyContinue
    Log "Scheduled task removed (user restarted manually)."
}

# Ui
[xml]$Xaml = @"
<Window
    xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation"
    xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml"
    Title="Windows 11 uuendus"
    Width="480" Height="340"
    WindowStartupLocation="CenterScreen"
    Topmost="True"
    ResizeMode="CanMinimize"
    WindowStyle="SingleBorderWindow"
    Background="#0F0F0F">

  <Window.Resources>
    <Style x:Key="PrimaryBtn" TargetType="Button">
      <Setter Property="Background"       Value="#0078D4"/>
      <Setter Property="Foreground"       Value="#FFFFFF"/>
      <Setter Property="FontSize"         Value="14"/>
      <Setter Property="FontWeight"       Value="SemiBold"/>
      <Setter Property="Height"           Value="42"/>
      <Setter Property="Width"            Value="180"/>
      <Setter Property="Cursor"           Value="Hand"/>
      <Setter Property="BorderThickness"  Value="0"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" CornerRadius="8"
                    Background="{TemplateBinding Background}">
              <ContentPresenter HorizontalAlignment="Center"
                                VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#1084D8"/>
              </Trigger>
              <Trigger Property="IsPressed" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#006BBD"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>

    <Style x:Key="SnoozeBtn" TargetType="Button">
      <Setter Property="Background"       Value="#1E1E1E"/>
      <Setter Property="Foreground"       Value="#A0A0A0"/>
      <Setter Property="FontSize"         Value="13"/>
      <Setter Property="Height"           Value="42"/>
      <Setter Property="Width"            Value="130"/>
      <Setter Property="Cursor"           Value="Hand"/>
      <Setter Property="BorderThickness"  Value="1"/>
      <Setter Property="BorderBrush"      Value="#2E2E2E"/>
      <Setter Property="Template">
        <Setter.Value>
          <ControlTemplate TargetType="Button">
            <Border x:Name="Bd" CornerRadius="8"
                    Background="{TemplateBinding Background}"
                    BorderBrush="{TemplateBinding BorderBrush}"
                    BorderThickness="{TemplateBinding BorderThickness}">
              <ContentPresenter HorizontalAlignment="Center"
                                VerticalAlignment="Center"/>
            </Border>
            <ControlTemplate.Triggers>
              <Trigger Property="IsMouseOver" Value="True">
                <Setter TargetName="Bd" Property="Background" Value="#252525"/>
              </Trigger>
            </ControlTemplate.Triggers>
          </ControlTemplate>
        </Setter.Value>
      </Setter>
    </Style>
  </Window.Resources>

  <Grid Margin="32,28,32,28">
    <Grid.RowDefinitions>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="16"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="20"/>
      <RowDefinition Height="Auto"/>
      <RowDefinition Height="20"/>
      <RowDefinition Height="Auto"/>
    </Grid.RowDefinitions>

    <!-- Header row: Windows logo + title -->
    <StackPanel Grid.Row="0" Orientation="Horizontal" VerticalAlignment="Center">
      <Viewbox Width="28" Height="28" Margin="0,0,12,0">
        <Canvas Width="88" Height="88">
          <Rectangle Canvas.Left="0"  Canvas.Top="0"  Width="40" Height="40" Fill="#00A4EF"/>
          <Rectangle Canvas.Left="48" Canvas.Top="0"  Width="40" Height="40" Fill="#FFB900"/>
          <Rectangle Canvas.Left="0"  Canvas.Top="48" Width="40" Height="40" Fill="#00B050"/>
          <Rectangle Canvas.Left="48" Canvas.Top="48" Width="40" Height="40" Fill="#E74856"/>
        </Canvas>
      </Viewbox>
      <StackPanel>
        <TextBlock Text="Restart Required"
                   FontSize="18" FontWeight="SemiBold"
                   Foreground="#F0F0F0"/>
        <TextBlock Text="Windows 11 uuendus"
                   FontSize="12" Foreground="#606060" Margin="0,2,0,0"/>
      </StackPanel>
    </StackPanel>

    <!-- Divider -->
    <Rectangle Grid.Row="1" Height="1" Fill="#1E1E1E"
               VerticalAlignment="Center" Margin="0,8,0,0"/>

    <!-- Body text -->
    <TextBlock Grid.Row="2"
               Text="Arvuti uuendas ennast Windows 11 versioonile. Palun taaskäivitage esimesel võimalusel pärast restarti kulub uuenduse lõpuleviimiseks umbes 30 minutit."
               FontSize="13" Foreground="#909090"
               TextWrapping="Wrap" LineHeight="20"/>

    <!-- Progress bar + countdown -->
    <Grid Grid.Row="4">
      <Grid.RowDefinitions>
        <RowDefinition Height="Auto"/>
        <RowDefinition Height="8"/>
        <RowDefinition Height="Auto"/>
      </Grid.RowDefinitions>

      <!-- Progress track -->
      <Border Grid.Row="0" Height="4" CornerRadius="2" Background="#1E1E1E">
        <Border x:Name="ProgressFill" HorizontalAlignment="Left"
                Height="4" CornerRadius="2"
                Background="#0078D4" Width="0"/>
      </Border>

      <!-- Fix 3: removed invalid HorizontalAlignment="Space Between" -->
      <StackPanel Grid.Row="2" Orientation="Horizontal">
        <TextBlock Text="Auto-restart in " FontSize="12" Foreground="#505050"/>
        <TextBlock x:Name="CountdownText"
           FontSize="12" FontWeight="SemiBold"
           Foreground="#0078D4"/>
      </StackPanel>
    </Grid>

    <!-- Buttons -->
    <StackPanel Grid.Row="6" Orientation="Horizontal"
                HorizontalAlignment="Right">
      <Button x:Name="SnoozeBtn" Content="Tuleta hiljem meelde"
              Style="{StaticResource SnoozeBtn}" Margin="0,0,10,0"/>
      <Button x:Name="RestartBtn" Content="Restardi nüüd"
              Style="{StaticResource PrimaryBtn}"/>
    </StackPanel>
  </Grid>
</Window>
"@

$Reader = New-Object System.Xml.XmlNodeReader $Xaml
$Window = [Windows.Markup.XamlReader]::Load($Reader)

$CountdownText = $Window.FindName("CountdownText")
$ProgressFill  = $Window.FindName("ProgressFill")
$RestartBtn    = $Window.FindName("RestartBtn")
$SnoozeBtn     = $Window.FindName("SnoozeBtn")

# Buttons
$RestartBtn.Add_Click({
    Log "User clicked Restart Now."
    CancelScheduledTask
    $Timer.Stop()
    $Window.Close()
    shutdown.exe /r /t 5 /c "Restarting now to complete Windows 11 25H2 upgrade."
})

$SnoozeBtn.Add_Click({
    Log "User snoozed — window minimized."
    $Window.WindowState = 'Minimized'
})

# Timer
$Timer = New-Object System.Windows.Threading.DispatcherTimer
$Timer.Interval = [TimeSpan]::FromSeconds(1)
$Timer.Add_Tick({
    $Remaining = $Deadline - (Get-Date)
    if ($Remaining.TotalSeconds -le 0) {
        Log "UI deadline reached. Scheduled task will handle reboot."
        $Timer.Stop()
        $Window.Close()
    } else {
        $CountdownText.Text = "{0:00}:{1:00}:{2:00}" -f `
            ($Remaining.Hours + $Remaining.Days * 24),
            $Remaining.Minutes,
            $Remaining.Seconds

        # Update progress bar width
        $Elapsed  = $TotalSeconds - $Remaining.TotalSeconds
        $Fraction = [Math]::Min($Elapsed / $TotalSeconds, 1)
        $MaxWidth = $Window.ActualWidth - 64
        $ProgressFill.Width = $Fraction * $MaxWidth
    }
})
$Timer.Start()

$Window.ShowDialog()