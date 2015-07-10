fs = require 'fs'
path = require 'path'
{BufferedProcess} = require 'atom'
{XRegExp} = require 'xregexp'


class LinterRust
  cargoDependencyDir: "target/debug/deps"
  lintProcess: null
  pattern: XRegExp('(?<file>.+):(?<from_line>\\d+):(?<from_col>\\d+):\\s*\
    (?<to_line>\\d+):(?<to_col>\\d+)\\s+\
    ((?<error>error|fatal error)|(?<warning>warning)|(?<info>note)):\\s+\
    (?<message>.+)\n', '')

  lint: (textEditor) =>
    return new Promise (resolve, reject) =>
      results = []
      file = @initCmd do textEditor.getPath
      curDir = path.dirname file
      @cmd.push file
      command = @cmd[0]
      options = {cwd: curDir}
      args = @cmd.slice 1

      stdout = (data) ->
        console.log data if do atom.inDevMode
      stderr = (err) ->
        results.push err

      exit = (code) =>
        if code is 101 or code is 0
          messages = @parse results.join('')
          messages.forEach (message) ->
            if !(path.isAbsolute message.filePath)
              message.filePath = path.join curDir, message.filePath
          resolve messages
        else
          resolve []

      @lintProcess = new BufferedProcess({command, args, options, stdout, stderr, exit})
      @lintProcess.onWillThrowError ({error, handle}) ->
        atom.notifications.addError "Failed to run #{command}",
          detail: "#{error.message}"
          dismissable: true
        handle()
        resolve []

  parse: (output) =>
    messages = []
    XRegExp.forEach output, @pattern, (match) ->
      type = if match.error
        "Error"
      else if match.warning
        "Warning"

      if match.from_col == match.to_col
        match.to_col = parseInt(match.to_col) + 1

      messages.push {
        type: type or 'Warning'
        text: match.message
        filePath: match.file
        range: [
          [match.from_line - 1, match.from_col - 1],
          [match.to_line - 1, match.to_col - 1]
        ]
      }
    return messages

  config: (key) ->
      atom.config.get "linter-rust.#{key}"


  initCmd: (editingFile) =>
    cargoManifestPath = @locateCargo path.dirname editingFile
    rustHome = @config 'rustHome'
    rustcPath = path.join rustHome, 'bin', 'rustc'
    cargoPath = path.join rustHome, 'bin', 'cargo'
    if not cargoPath or not @config('useCargo') or not cargoManifestPath
      @cmd = [rustcPath, '-Z', 'no-trans', '--color', 'never']
      if cargoManifestPath
        @cmd.push '-L'
        @cmd.push path.join path.dirname(cargoManifestPath), @cargoDependencyDir
      return editingFile
    else
      @cmd = [cargoPath, 'build', '-j', @config('jobsNumber'), '--manifest-path']
      return cargoManifestPath


  locateCargo: (curDir) =>
    root_dir = if /^win/.test process.platform then /^.:\\$/ else /^\/$/
    cargoManifestFilename = @config 'cargoManifestFilename'
    directory = path.resolve curDir
    loop
      return path.join directory, cargoManifestFilename if fs.existsSync path.join directory, cargoManifestFilename
      break if root_dir.test directory
      directory = path.resolve path.join(directory, '..')
    return false



module.exports = LinterRust
