import { defineConfig } from "vite";
import tailwindcss from "@tailwindcss/vite";

export default {
	vite: defineConfig({
		plugins: [tailwindcss()],
	}),
	headTagsTemplate(context) {
		return `
<link rel="stylesheet" href="/style.css" />
<meta name="generator" content="elm-pages v${context.cliVersion}" />
<meta name="author" content="Mehdi Hassan" />
`;
	},
	preloadTagForFile(file) {
		// add preload directives for JS assets and font assets, etc., skip for CSS files
		// this function will be called with each file that is processed by Vite, including any files in your headTagsTemplate in your config
		return !file.endsWith(".css");
	},
};
