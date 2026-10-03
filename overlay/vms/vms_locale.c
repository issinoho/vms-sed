/* vms_locale.c - take the locale from environment variables on OpenVMS.

   The OpenVMS CRTL's setlocale (category, "") reads the locale only from
   logical names (LC_ALL, LC_CTYPE, ..., LANG).  Programs started by GNV
   bash receive these as environment variables instead, which getenv()
   sees but setlocale() ignores, so sed would stay in the C locale.

   sed's main calls vms_locale_from_environment () right after
   setlocale (LC_ALL, "") (patch 0003).  For each category it resolves the
   POSIX precedence (LC_ALL, then LC_<category>, then LANG) with getenv(),
   which covers both environment variables and logical names, and selects
   that locale explicitly.  Unknown names are ignored, leaving what the
   CRTL chose.

   Part of the OpenVMS port of GNU sed; distributed under the GNU
   General Public License, version 3 or later.  */

#include <config.h>

#include <locale.h>
#include <stdlib.h>

#include "vms_locale.h"

static const char *
env_locale (const char *name)
{
  const char *value = name ? getenv (name) : NULL;
  return value && *value ? value : NULL;
}

void
vms_locale_from_environment (void)
{
  static const struct { int category; const char *var; } categories[] = {
    { LC_COLLATE, "LC_COLLATE" },
    { LC_CTYPE, "LC_CTYPE" },
    { LC_MONETARY, "LC_MONETARY" },
    { LC_NUMERIC, "LC_NUMERIC" },
    { LC_TIME, "LC_TIME" },
#ifdef LC_MESSAGES
    { LC_MESSAGES, "LC_MESSAGES" },
#endif
  };
  size_t i;

  for (i = 0; i < sizeof categories / sizeof categories[0]; i++)
    {
      const char *name = env_locale ("LC_ALL");
      if (!name)
        name = env_locale (categories[i].var);
      if (!name)
        name = env_locale ("LANG");
      if (name)
        setlocale (categories[i].category, name);
    }
}
