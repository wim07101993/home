# The media library is MOUNTED whole and BACKED UP in part. /export/media is
# 8.4 TB against 4.5 TB free on the Storage Box, so backing up the directory
# would fill the box and stop every other backup with it.
#
# The 48 below are a deliberate choice about what is worth off-site. They were
# in samson.tf until 2026-09-29; they are plex's library, so they live here.
#
# /export/media is a bind of the same directory plex itself mounts -- same
# device and inode, verified 2026-09-29.
output "backup" {
  value = {
    mounts = { media = "/export/media" }
    paths = [
      "/backup/media/live",
      "/backup/media/movies/animated/1990-1999/The Lion King (1994)",
      "/backup/media/movies/animated/1990-1999/The Lion King II Simbas Pride (1998)",
      "/backup/media/movies/animated/2000-2009/Bob De Bouwer - Hoe Bob Een Bouwer Werd (2008)",
      "/backup/media/movies/animated/2000-2009/Bob de Bouwer - Molly geeft eerste hulp (2004)",
      "/backup/media/movies/animated/2000-2009/Bob de Bouwer - Race naar de finish (2008)",
      "/backup/media/movies/animated/2000-2009/Bob de Bouwer Werk in Uitvoering - Bob's Grote Plan (2005)",
      "/backup/media/movies/animated/2000-2009/Bob de Bouwer werk in uitvoering- Ridder Muck (2007)",
      "/backup/media/movies/animated/2000-2009/Bob de bouwer - Leve het wilde westen (2007)",
      "/backup/media/movies/animated/2000-2009/Bob de bouwer - Wendy's drukke dag (2004)",
      "/backup/media/movies/animated/2000-2009/Bob de bouwer Werk in uitvoering - Crossen met Scrambler (2006)",
      "/backup/media/movies/animated/2000-2009/Bob de bouwer en de ridders van Makelot (2004)",
      "/backup/media/movies/animated/2000-2009/Bob de bouwer werk in uitvoering - De oogst van Spud (2006)",
      "/backup/media/movies/animated/2000-2009/Bob de bouwer werk in uitvoering ‐ Packers eerste dag (2008)",
      "/backup/media/movies/animated/2000-2009/The Lion King 1½ (2004)",
      "/backup/media/series/animated/Alfred J. Kwak",
      "/backup/media/series/animated/Avatar - The Last Airbender (2005)/Season 01 - Water (2005)",
      "/backup/media/series/animated/Buurman & Buurman (1976)",
      "/backup/media/series/animated/Danny Phantom (2004)",
      "/backup/media/series/animated/David de kabouter",
      "/backup/media/series/animated/De fabeltjeskrant",
      "/backup/media/series/animated/De smufen",
      "/backup/media/series/animated/Dragonball (1986)",
      "/backup/media/series/animated/Er Was Eens ... De aarde",
      "/backup/media/series/animated/Er Was Eens ... De mens",
      "/backup/media/series/animated/Er Was Eens ... De ruimte",
      "/backup/media/series/animated/Er was eens ... Het Leven",
      "/backup/media/series/animated/Lucky Luke",
      "/backup/media/series/animated/Maya De Bij",
      "/backup/media/series/animated/Nick Bruna's Nijntje (1984)",
      "/backup/media/series/animated/Nijntje En Vriendjes (2003)",
      "/backup/media/series/animated/Noahs Island (1997)",
      "/backup/media/series/animated/Plonsters (1987)",
      "/backup/media/series/animated/Plonsters (1987)/Season 01",
      "/backup/media/series/animated/The Animals of Farthing Wood (1993)",
      "/backup/media/series/animated/Tiktak",
      "/backup/media/series/animated/Tiktak (2019-2020)",
      "/backup/media/series/live-action/'Allo 'Allo! (1982)",
      "/backup/media/series/live-action/Bumba",
      "/backup/media/series/live-action/Dag Sinterklaas",
      "/backup/media/series/live-action/Doctor Who (1963)",
      "/backup/media/series/live-action/Drake & Josh (2004)",
      "/backup/media/series/live-action/Kabouter Plop",
      "/backup/media/series/live-action/Kulderzipken",
      "/backup/media/series/live-action/Mythbusters (2003)",
      "/backup/media/series/live-action/Spring",
      "/backup/media/series/live-action/Teletubbies nl (1997)",
      "/backup/media/series/live-action/W817",
    ]
  }
}
