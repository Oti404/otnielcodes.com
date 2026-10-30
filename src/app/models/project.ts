export type ProjectStatus = 'live' | 'beta' | 'wip' | 'archived';

/** O intrare din src/assets/projects.json. */
export interface Project {
  name: string;
  /** Descriere scurtă, pe o singură linie. */
  description: string;
  technologies: string[];
  liveUrl?: string | null;
  repoUrl?: string | null;
  /** Cale relativă (ex. "assets/projects/car-world.webp") sau URL absolut. */
  image?: string | null;
  /** Stadiul proiectului, setat manual. Lipsă = "live". */
  status?: ProjectStatus | null;
}

/** Rezultatul verificării automate (status.json, generat de .github/workflows/status.yml). */
export interface LiveCheck {
  up: boolean;
  code: number | null;
  ms: number | null;
}

export interface StatusReport {
  checkedAt: string;
  projects: Record<string, LiveCheck>;
}
