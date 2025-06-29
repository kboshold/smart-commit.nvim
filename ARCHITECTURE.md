# Smart Commit Architecture

This document provides a technical overview of the Smart Commit plugin's architecture, internal components, and data flow.

## Overview

Smart Commit is designed as a modular, event-driven system that leverages Neovim 0.11's asynchronous APIs to provide a responsive user experience. The plugin is structured around several key components:

1. **Configuration System**: Hierarchical configuration loading and merging
2. **Task Runner**: Asynchronous task execution with dependency tracking
3. **UI Components**: Real-time feedback through sticky headers and sign column
4. **Predefined Tasks**: Reusable task templates for common operations
5. **API Layer**: Public interfaces for extension and integration

## Core Components

### Configuration System (`config.lua`)

The configuration system loads and merges settings from multiple sources in order of precedence:

1. Plugin defaults
2. User global config (`~/.smart-commit.lua`)
3. Project-specific config (first `.smart-commit.lua` found in directory hierarchy)
4. Runtime setup options

Key functions:
- `load_config()`: Loads and merges configuration from all sources
- `find_file_upwards()`: Traverses directory hierarchy to find config files
- `process_tasks()`: Resolves task extensions and handles shorthand syntax

### Task Runner (`runner.lua`)

The task runner is responsible for executing tasks asynchronously and managing their lifecycle:

- Uses `vim.system()` for non-blocking command execution
- Implements a dependency graph for task ordering
- Provides real-time status updates through UI callbacks

Key components:
- Task states: `PENDING`, `WAITING`, `RUNNING`, `SUCCESS`, `FAILED`, `SKIPPED`
- `run_tasks_with_dependencies()`: Main entry point for task execution
- `run_task()`: Executes a single task based on its configuration
- `run_command()`: Handles shell command execution
- `update_ui()`: Updates the UI with current task states

### UI Components (`ui.lua`)

The UI system provides visual feedback through:

1. **Sticky Header**: A non-intrusive split window showing task status
2. **Sign Column**: Icons indicating overall task status
3. **Analysis Window**: Side panel for displaying detailed task output

Key functions:
- `set()`: Creates or updates the header content
- `toggle()`: Shows or hides the header
- `show_analysis()`: Creates a side panel for detailed output
- `update_signs()`: Updates the sign column indicators

### Types System (`types.lua`)

Centralized type definitions using EmmyLua annotations for LSP support:

- `SmartCommitTask`: Core task definition
- `SmartCommitConfig`: Plugin configuration structure
- `StickyHeaderContent`: UI content structure
- Various utility types for callbacks and handlers

### Predefined Tasks (`predefined/`)

Reusable task templates for common operations:

- **PNPM Tasks**: Package management and script execution
- **Copilot Tasks**: AI-powered commit message generation and code analysis

## Data Flow

1. **Initialization**:
   - Plugin loads on Neovim startup
   - Configuration is loaded and merged
   - Autocommands are set up to detect commit buffers

2. **Activation**:
   - Git commit buffer is opened
   - Autocommand triggers `on_commit_buffer_open()`
   - Initial UI is displayed
   - Task runner is initialized

3. **Task Execution**:
   - Tasks are filtered based on `when` conditions
   - Dependencies are resolved
   - Tasks without dependencies start executing
   - As tasks complete, dependent tasks are queued

4. **UI Updates**:
   - Timer-based UI updates show real-time progress
   - Task states are reflected in the sticky header
   - Sign column shows overall status
   - Detailed analysis is shown in side panels when available

5. **Completion**:
   - All tasks complete (success, failure, or skipped)
   - Final UI state is displayed
   - Update timer is stopped

## Extension Points

Smart Commit is designed to be extensible in several ways:

1. **Task Registration**: Register custom tasks via the API
2. **Task Extension**: Extend predefined tasks with custom behavior
3. **Configuration Files**: Project-specific configuration
4. **Custom Handlers**: Advanced task handling with full context access

## Internal State Management

The plugin maintains several key state objects:

1. **Task States**: Current state of each task in `runner.tasks`
2. **UI States**: Header and analysis window state in `ui.header_states`
3. **Configuration**: Merged configuration in `M.config`

## Performance Considerations

- Asynchronous execution ensures the editor remains responsive
- UI updates are throttled to reduce overhead
- Tasks can run in parallel up to the configured concurrency limit
- All UI updates are scheduled to run on the main thread

## Error Handling

- Task failures are captured and displayed in the UI
- Command execution errors are logged and reflected in task state
- Configuration errors are reported via notifications
- Timeouts prevent tasks from running indefinitely

## Future Improvements

1. **Task Caching**: Cache task results to avoid redundant execution
2. **Task Grouping**: Group related tasks for better organization
3. **Custom UI Themes**: Allow customization of UI appearance
4. **Task Retry**: Automatic retry for failed tasks
5. **Task History**: Persistent history of task execution results
