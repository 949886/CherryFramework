using Godot;
using System;
using System.Collections.Generic;

/// <summary>
/// Process-wide generated registry used by every Cherry <see cref="Navigator"/>.
/// </summary>
[GlobalClass]
public partial class PageRegistry : Resource
{
    private static PageRegistry? _instance;
    private Dictionary<string, PageDefinition>? _byPath;
    private Dictionary<Type, PageDefinition>? _byType;

    /// <summary>
    /// Gets the generated registry resource path.
    /// </summary>
    /// <remarks>
    /// The Navigation module publishes the preferred location in Project Settings
    /// under <c>cherry/navigation/page_registry_path</c>. If the setting is missing,
    /// Cherry derives its root from the globally registered PluginModule script.
    /// </remarks>
    public static string RegistryPath
    {
        get
        {
            string configuredPath = ProjectSettings.GetSetting("cherry/navigation/page_registry_path", "").AsString();
            if (configuredPath.Length != 0)
                return configuredPath;
            string cherryRoot = FindCherryRoot();
            if (cherryRoot.Length == 0)
            {
                GD.PushError("Cherry Navigation: unable to locate Cherry root.");
                return "";
            }
            return cherryRoot.PathJoin("generated/page_registry.tres");
        }
    }

    /// <summary>
    /// Gets the single process-local PageRegistry instance.
    /// </summary>
    /// <remarks>No Godot Autoload is used.</remarks>
    public static PageRegistry Instance
    {
        get
        {
            if (_instance != null)
                return _instance;
            string registryPath = RegistryPath;
            if (registryPath.Length != 0 && ResourceLoader.Exists(registryPath))
            {
                PageRegistry? loaded = ResourceLoader.Load<PageRegistry>(registryPath, "", ResourceLoader.CacheMode.Ignore);
                if (loaded != null)
                    return _instance = loaded;
            }
            return _instance = new PageRegistry();
        }
    }

    /// <summary>Generated static page definitions.</summary>
    [Export] public Godot.Collections.Array<PageDefinition> Pages { get; set; } = new();

    private static string FindCherryRoot()
    {
        foreach (Godot.Collections.Dictionary classInfo in ProjectSettings.GetGlobalClassList())
        {
            if (classInfo["class"].AsString() != "PluginModule")
                continue;
            string scriptPath = classInfo["path"].AsString();
            return scriptPath.Length == 0 ? "" : scriptPath.GetBaseDir().GetBaseDir();
        }
        return "";
    }

    /// <summary>
    /// Normalizes <paramref name="path"/> into Cherry's canonical <c>ui://...</c>
    /// representation.
    /// </summary>
    /// <returns>An empty string when the input is not a supported navigation path.</returns>
    public static string NormalizePath(string path)
    {
        if (string.IsNullOrWhiteSpace(path))
            return "";
        string raw = path.Trim();
        if (raw == "/" || raw == "ui://")
            return "ui://";
        string suffix;
        if (raw.StartsWith("ui://", StringComparison.Ordinal))
            suffix = raw[5..];
        else if (raw.StartsWith("/", StringComparison.Ordinal))
            suffix = raw[1..];
        else
            return "";
        suffix = suffix.Trim('/');
        if (suffix.Length == 0)
            return "ui://";
        if (suffix.Contains("://", StringComparison.Ordinal))
            return "";
        return "ui://" + suffix;
    }

    /// <summary>Resolves a dynamic route path or throws when it is not registered.</summary>
    public PageDefinition Resolve(string path)
    {
        if (!TryResolve(path, out PageDefinition definition))
            throw new InvalidOperationException($"Navigation page not found: {path}");
        return definition;
    }

    /// <summary>Attempts to resolve a dynamic route path without throwing.</summary>
    public bool TryResolve(string path, out PageDefinition definition)
    {
        EnsurePathIndex();
        string normalized = NormalizePath(path);
        if (normalized.Length == 0)
        {
            definition = null!;
            return false;
        }
        return _byPath!.TryGetValue(normalized, out definition!);
    }

    /// <summary>Returns whether <paramref name="path"/> is currently registered.</summary>
    public bool Contains(string path) => TryResolve(path, out _);

    /// <summary>
    /// Resolves the unique page definition whose instantiated scene root has type
    /// <typeparamref name="TPage"/>.
    /// </summary>
    /// <exception cref="InvalidOperationException">
    /// Thrown when no registered definition uses the requested type or when the
    /// type index cannot be built unambiguously.
    /// </exception>
    public PageDefinition Resolve<TPage>() where TPage : NavigationPage
    {
        EnsureTypeIndex();
        if (!_byType!.TryGetValue(typeof(TPage), out PageDefinition? definition))
            throw new InvalidOperationException($"No registered page scene has root type {typeof(TPage).FullName}.");
        return definition;
    }

    /// <summary>Attempts to resolve a page definition by concrete page type.</summary>
    public bool TryResolve<TPage>(out PageDefinition definition) where TPage : NavigationPage
    {
        EnsureTypeIndex();
        return _byType!.TryGetValue(typeof(TPage), out definition!);
    }

    /// <summary>
    /// Replaces all generated definitions and immediately invalidates/rebuilds
    /// runtime lookup indexes.
    /// </summary>
    public void ReplacePages(IReadOnlyList<PageDefinition> newPages)
    {
        Pages.Clear();
        foreach (PageDefinition page in newPages)
            Pages.Add(page);
        InvalidateIndexes();
        EnsurePathIndex();
    }

    /// <summary>
    /// Returns whether the supplied definitions contain the same ordered Path
    /// and Scene entries.
    /// </summary>
    public bool ContentEquals(IReadOnlyList<PageDefinition> otherPages)
    {
        if (Pages.Count != otherPages.Count)
            return false;
        for (int i = 0; i < Pages.Count; i++)
        {
            PageDefinition current = Pages[i];
            PageDefinition other = otherPages[i];
            if (current == null || other == null || !string.Equals(current.Path, other.Path, StringComparison.Ordinal))
                return false;
            if (current.Scene == null || other.Scene == null || !string.Equals(current.Scene.ResourcePath, other.Scene.ResourcePath, StringComparison.Ordinal))
                return false;
        }
        return true;
    }

    /// <summary>Invalidates and rebuilds runtime registry indexes.</summary>
    public void RebuildIndexes()
    {
        InvalidateIndexes();
        EnsurePathIndex();
    }

    private void InvalidateIndexes()
    {
        _byPath = null;
        _byType = null;
    }

    private void EnsurePathIndex()
    {
        if (_byPath != null)
            return;
        _byPath = new Dictionary<string, PageDefinition>(StringComparer.Ordinal);
        foreach (PageDefinition page in Pages)
        {
            if (page == null)
                continue;
            string normalized = NormalizePath(page.Path);
            if (normalized.Length == 0)
                continue;
            if (!_byPath.TryAdd(normalized, page))
                throw new InvalidOperationException($"Duplicate navigation path: {normalized}");
        }
    }

    private void EnsureTypeIndex()
    {
        if (_byType != null)
            return;
        _byType = new Dictionary<Type, PageDefinition>();
        foreach (PageDefinition definition in Pages)
        {
            if (definition?.Scene == null)
                continue;
            Node node = definition.Scene.Instantiate();
            try
            {
                if (node is not NavigationPage)
                    continue;
                Type type = node.GetType();
                if (_byType.ContainsKey(type))
                    throw new InvalidOperationException($"Multiple registered pages use root type {type.FullName}.");
                _byType[type] = definition;
            }
            finally
            {
                node.Free();
            }
        }
    }
}
