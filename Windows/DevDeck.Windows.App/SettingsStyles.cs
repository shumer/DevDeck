using System.Windows;
using System.Windows.Controls;
using System.Windows.Markup;

namespace DevDeck.Windows.App;

internal static class SettingsStyles
{
    internal static Style TextBoxStyle { get; } = (Style)XamlReader.Parse("""
        <Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" TargetType="TextBox">
          <Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="#DDDDDD"/>
          <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="TextBox">
            <Border x:Name="field" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="1" CornerRadius="6" Padding="{TemplateBinding Padding}">
              <ScrollViewer x:Name="PART_ContentHost" VerticalScrollBarVisibility="{TemplateBinding ScrollViewer.VerticalScrollBarVisibility}" HorizontalScrollBarVisibility="{TemplateBinding ScrollViewer.HorizontalScrollBarVisibility}"/>
            </Border>
            <ControlTemplate.Triggers><Trigger Property="IsKeyboardFocused" Value="True"><Setter TargetName="field" Property="BorderBrush" Value="#3478F4"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger></ControlTemplate.Triggers>
          </ControlTemplate></Setter.Value></Setter>
        </Style>
        """);
    internal static Style ButtonStyle { get; } = (Style)XamlReader.Parse("""
        <Style xmlns="http://schemas.microsoft.com/winfx/2006/xaml/presentation" TargetType="Button">
          <Setter Property="Background" Value="White"/><Setter Property="BorderBrush" Value="#D2D7DF"/><Setter Property="BorderThickness" Value="1"/>
          <Setter Property="Foreground" Value="#253043"/>
          <Setter Property="Template"><Setter.Value><ControlTemplate TargetType="Button">
            <Border x:Name="frame" xmlns:x="http://schemas.microsoft.com/winfx/2006/xaml" CornerRadius="6" Padding="{TemplateBinding Padding}" Background="{TemplateBinding Background}" BorderBrush="{TemplateBinding BorderBrush}" BorderThickness="{TemplateBinding BorderThickness}">
              <ContentPresenter HorizontalAlignment="Center" VerticalAlignment="Center" RecognizesAccessKey="True"/>
            </Border>
            <ControlTemplate.Triggers><Trigger Property="IsMouseOver" Value="True"><Setter TargetName="frame" Property="Background" Value="#E9EFF7"/></Trigger><Trigger Property="IsEnabled" Value="False"><Setter Property="Opacity" Value="0.5"/></Trigger></ControlTemplate.Triggers>
          </ControlTemplate></Setter.Value></Setter>
        </Style>
        """);
    internal static void AddTo(ResourceDictionary resources)
    {
        resources[typeof(TextBox)] = TextBoxStyle;
        resources[typeof(Button)] = ButtonStyle;
    }
}
