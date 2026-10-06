// ignore_for_file: constant_identifier_names, non_constant_identifier_names

const API_URL = String.fromEnvironment('API_URL');
const COMMENTUM_API_URL = String.fromEnvironment('COMMENTUM_API_URL');

const ONESIGNAL_APP_ID = String.fromEnvironment('ONESIGNAL_APP_ID');
const ADMIN_ANILIST_ID = String.fromEnvironment(
  'ADMIN_ANILIST_ID',
  defaultValue: '8013267',
);
const _ANIDASH_ADMIN_API_URL = String.fromEnvironment('ANIDASH_ADMIN_API_URL');
final ANIDASH_ADMIN_API_URL =
    _ANIDASH_ADMIN_API_URL.trim().isEmpty
        ? 'https://anidashweb.vercel.app/api'
        : _ANIDASH_ADMIN_API_URL.trim().replaceFirst(RegExp(r'/$'), '');

const ANILIST_CLIENT_ID = String.fromEnvironment(
  'ANILIST_CLIENT_ID',
  defaultValue: '50037|52962',
);
const ANILIST_CLIENT_SECRET = String.fromEnvironment(
  'ANILIST_CLIENT_SECRET',
  defaultValue:
      'inpCGvXD5r2UglDrE6UHslYdSbW8GNBCBbgddDzW|cZEcp7iSA5jm730eJ0lJ13ACuZdPPFCLtLu2Typj',
);

const MAL_CLIENT_ID = String.fromEnvironment(
  'MAL_CLIENT_ID',
  defaultValue: 'dafce95c66734efefa19650c84178416',
);
const MAL_CLIENT_SECRET = String.fromEnvironment(
  'MAL_CLIENT_SECRET',
  defaultValue: '',
);
