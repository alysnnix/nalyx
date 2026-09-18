/**
 * The two external binaries this plugin shells out to.
 *
 * The Nix package pins both to absolute store paths at build time, because the daemon's PATH is
 * whatever the login profile happened to export and a plugin that only speaks on some machines is
 * worse than one that fails at build. The environment variables stay as an escape hatch for
 * running the plugin straight from a checkout.
 */
export const FFPLAY = process.env.PASEO_TTS_FFPLAY ?? "ffplay";

export const OMP = process.env.PASEO_TTS_OMP ?? "omp";
