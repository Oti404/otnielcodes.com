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
}
