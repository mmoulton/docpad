# Requires
pathUtil = require('path')
balUtil = require('bal-util')
_ = require('underscore')
mime = require('mime')

# Local
{Backbone,Model} = require(__dirname+'/../base')


# ---------------------------------
# File Model

class FileModel extends Model

	# ---------------------------------
	# Properties

	# The out directory path to put the file
	outDirPath: null

	# Model Type
	type: 'file'

	# Stat Object
	stat: null


	# ---------------------------------
	# Attributes

	defaults:

		# ---------------------------------
		# Automaticly set variables

		# The unique document identifier
		id: null

		# The file's name without the extension
		basename: null

		# The file's last extension
		# "hello.md.eco" -> "eco"
		extension: null

		# The file's extensions as an array
		# "hello.md.eco" -> ["md","eco"]
		extensions: null  # Array

		# The file's name with the extension
		filename: null

		# The full path of our source file, only necessary if called by @load
		fullPath: null

		# The full directory path of our source file
		fullDirPath: null

		# The final rendered path of our file
		outPath: null

		# The final rendered path of our file's directory
		outDirPath: null

		# The relative path of our source file (with extensions)
		relativePath: null

		# The relative directory path of our source file
		relativeDirPath: null

		# The relative base of our source file (no extension)
		relativeBase: null

		# The MIME content-type for the source document
		contentType: null


		# ---------------------------------
		# Content variables

		# The contents of the file, stored as a Buffer
		data: null

		# The encoding of the file
		encoding: null

		# The contents of the file, stored as a String
		content: null


		# ---------------------------------
		# User set variables

		# The title for this document
		title: null

		# The date object for this document
		date: null

		# The generated slug (url safe seo title) for this document
		slug: null

		# The url for this document
		url: null

		# Alternative urls for this document
		urls: null  # Array

		# Whether or not we ignore this document (do not render it)
		ignored: false



	# ---------------------------------
	# Functions

	# Initialize
	initialize: (data,options) ->
		# Prepare
		{outDirPath,stat} = options

		# Apply
		@outDirPath = outDirPath  if outDirPath
		@setStat(stat)  if stat
		@set(
			extensions: []
			urls: []
		)

		# Super
		super

	# Get the arguments for the action
	# Using this contains the transparency with using opts, and not using opts
	getActionArgs: (opts,next) ->
		if typeof opts is 'function' and next? is false
			next = opts
			opts = {}
		else
			opts or= {}
		next or= opts.next or null
		return {next,opts}

	# Set Stat
	setStat: (stat) ->
		@stat = stat
		@set(
			ctime: new Date(stat.ctime)
			mtime: new Date(stat.mtime)
		)
		@

	# Get Attributes
	getAttributes: ->
		return @toJSON()

	# Get Meta
	getMeta: ->
		return @meta

	# Is Text?
	isText: ->
		return @get('encoding') isnt 'binary'

	# Is Binary?
	isBinary: ->
		return @get('encoding') is 'binary'

	# Load
	# If the fullPath exists, load the file
	# If it doesn't, then parse and normalize the file
	load: (opts={},next) ->
		# Prepare
		{opts,next} = @getActionArgs(opts,next)
		file = @
		filePath = @get('relativePath') or @get('fullPath') or @get('filename')
		fullPath = @get('fullPath')
		data = @get('data')

		# Log
		file.log('debug', "Loading the file: #{filePath}")

		# Handler
		complete = (err) ->
			return next(err)  if err
			file.log('debug', "Loaded the file: #{filePath}")
			next()

		# Exists?
		balUtil.exists fullPath, (exists) =>
			# Read the file
			if exists
				@readFile(fullPath, complete)
			else
				@parseData data, (err) =>
					return next(err)  if err
					@normalize (err) =>
						return next(err)  if err
						complete()

		# Chain
		@

	# Read File
	# Reads in the source file and parses it
	# next(err)
	readFile: (fullPath,next) ->
		# Prepare
		file = @
		fullPath = @get('fullPath')

		# Log
		file.log('debug', "Reading the file: #{fullPath}")

		# Async
		tasks = new balUtil.Group (err) =>
			if err
				file.log('err', "Failed to read the file: #{fullPath}")
				return next(err)
			else
				@normalize (err) =>
					return next(err)  if err
					file.log('debug', "Read the file: #{fullPath}")
					next()
		tasks.total = 2

		# Stat the file
		if file.stat
			tasks.complete()
		else
			balUtil.stat fullPath, (err,fileStat) ->
				return next(err)  if err
				file.stat = fileStat
				tasks.complete()

		# Read the file
		balUtil.readFile fullPath, (err,data) ->
			return next(err)  if err
			file.parseData(data, tasks.completer())

		# Chain
		@

	# Get the encoding of a buffer
	getEncoding: (buffer) ->
		# Prepare
		contentStartBinary = buffer.toString('binary',0,24)
		contentStartUTF8 = buffer.toString('utf8',0,24)
		encoding = 'utf8'

		# Detect encoding
		for i in [0...contentStartUTF8.length]
			charCode = contentStartUTF8.charCodeAt(i)
			if charCode is 65533 or charCode <= 8
				# 8 and below are control characters (e.g. backspace, null, eof, etc.)
				# 65533 is the unknown character
				encoding = 'binary'
				break

		# Return encoding
		return encoding

	# Parse data
	# Parses some data, and loads the meta data and content from it
	# next(err)
	parseData: (data,next) ->
		# Wipe everything
		backup = @toJSON()
		@clear()
		encoding = 'utf8'

		# Reset the file properties back to their originals
		@set(
			data: data
			basename: backup.basename
			extension: backup.extension
			extensions: backup.extensions
			filename: backup.filename
			fullPath: backup.fullPath
			outPath: backup.outPath
			outDirPath: backup.outDirPath
			relativePath: backup.relativePath
			relativeBase: backup.relativeBase
			contentType: backup.contentType
			urls: []
		)

		# Extract content from data
		if data instanceof Buffer
			encoding = @getEncoding(data)
			if encoding is 'binary'
				content = ''
			else
				content = data.toString(encoding)
		else if typeof data is 'string'
			content = data
		else
			content = ''

		# Trim the content
		content = content.replace(/\r\n?/gm,'\n').replace(/\t/g,'    ')

		# Apply
		@set({content,encoding})

		# Next
		next()
		@

	# Set the url for the file
	setUrl: (url) ->
		@addUrl(url)
		@set(url: url)
		@

	# Add a url
	# Allows our file to support multiple urls
	addUrl: (url) ->
		# Multiple Urls
		if url instanceof Array
			for newUrl in url
				@addUrl(newUrl)

		# Single Url
		else if url
			found = false
			urls = @get('urls')
			for own existingUrl in urls
				if existingUrl is url
					found = true
					break
			urls.push(url)  if not found

		# Chain
		@

	# Remove a url
	# Removes a url from our file
	removeUrl: (userUrl) ->
		urls = @get('urls')
		for url,index in urls
			if url is userUrl
				urls.remove(index)
				break
		@

	# Normalize data
	# Normalize any parsing we have done, as if a value has updates it may have consequences on another value. This will ensure everything is okay.
	# next(err)
	normalize: (opts={},next) ->
		# Prepare
		{opts,next} = @getActionArgs(opts,next)
		basename = @get('basename')
		filename = @get('filename')
		fullPath = @get('fullPath')
		relativePath = @get('relativePath')
		id = @get('id')
		date = @get('date')

		# Adjust
		fullPath or= filename
		relativePath or= null

		# Paths
		filename = pathUtil.basename(fullPath)
		basename = filename.replace(/\..*/, '')

		# Extension
		extensions = filename.split(/\./g)
		extensions.shift()
		extension = if extensions.length then extensions[extensions.length-1] else null

		# Paths
		fullDirPath = pathUtil.dirname(fullPath) or ''
		relativeDirPath = pathUtil.dirname(relativePath).replace(/^\.$/,'') or ''
		relativeBase =
			if relativeDirPath.length
				pathUtil.join(relativeDirPath, basename)
			else
				basename
		id or= relativePath or fullPath

		# Date
		date or= new Date(@stat.mtime)  if @stat

		# Mime type
		contentType = mime.lookup(fullPath)

		# Apply
		@set({basename,filename,fullPath,relativePath,fullDirPath,relativeDirPath,id,relativeBase,extensions,extension,contentType,date})

		# Next
		next()
		@

	# Contextualize data
	# Put our data into perspective of the bigger picture. For instance, generate the url for it's rendered equivalant.
	# next(err)
	contextualize: (opts={},next) ->
		# Fetch
		{opts,next} = @getActionArgs(opts,next)
		relativeBase = @get('relativeBase')
		extensions = @get('extensions')
		filename = @get('filename')
		url = null
		slug = null
		name = null
		outPath = null

		# Adjust
		url or= if extensions.length then "/#{relativeBase}.#{extensions.join('.')}" else "/#{relativeBase}"
		slug or= balUtil.generateSlugSync(relativeBase)
		name or= filename
		outPath = if @outDirPath then pathUtil.join(@outDirPath,url) else null
		outDirPath = pathUtil.dirname(outPath)
		@addUrl(url)

		# Apply
		@set({url,slug,name,outPath,outDirPath})

		# Forward
		next()
		@

	# Write the rendered file
	# next(err)
	write: (next) ->
		# Prepare
		file = @
		fileOutPath = @get('outPath')
		contentOrData = @get('content') or @get('data')

		# Log
		file.log 'debug', "Writing the file: #{fileOutPath}"

		# Write data
		balUtil.writeFile fileOutPath, contentOrData, (err) ->
			# Check
			return next(err)  if err

			# Log
			file.log 'debug', "Wrote the file: #{fileOutPath}"

			# Next
			next()

		# Chain
		@

	# Delete the file
	# next(err)
	delete: (next) ->
		# Prepare
		file = @
		fileOutPath = @get('outPath')

		# Log
		file.log 'debug', "Delete the file: #{fileOutPath}"

		# Write data
		balUtil.unlink fileOutPath, (err) ->
			# Check
			return next(err)  if err

			# Log
			file.log 'debug', "Deleted the file: #{fileOutPath}"

			# Next
			next()

		# Chain
		@

# Export
module.exports = FileModel
