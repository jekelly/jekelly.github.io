const { EleventyHtmlBasePlugin } = require("@11ty/eleventy");

module.exports = function (eleventyConfig) {
  // necessary to automatically prepend the prefix to internal links
  eleventyConfig.addPlugin(EleventyHtmlBasePlugin);
  eleventyConfig.addPassthroughCopy("se");
  eleventyConfig.ignores.add("se/**");
  eleventyConfig.addPassthroughCopy("CNAME");
  return {
    // prefix used by GitHub Pages, usually your project name
    pathPrefix: "/jekelly.github.io/"
  }
};
