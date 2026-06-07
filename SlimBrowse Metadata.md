# SlimBrowse Metadata

The following is a summary of the metadata returned by the XMLBrowser based CLI commands - if requested and available.
In order to request raw metadata, add the `tags:...` parameter to those SlimBrowse queries. The results may vary
depending on the service providing the data. Eg. Podcasts on TuneIn don't have a publishing date, but it's embedded
in the description. And they don't provide an author or publisher.

## Albums
* hasMetadata `album`
* album (name)
* artist
* artists
* genre
* year

## Artists
* hasMetadata `artist`
* artist

## Tracks
* hasMetadata `track`
* title
* album (name)
* artist (name)
* artists
* tracknum
* duration
* year

## Playlists
* hasMetadata: `playlist`
* title
* description

## Radio Station
* hasMetadata: `station`
* name
* description

## Podcasts
* hasMetadata `podcast`
* title
* publisher
* description

## Podcast Episodes
* hasMetadata `episode`
* title
* podcast (the show's name if available)
* description
* duration
* date (of the episode's publishing)


