<template>
  <AppProvider>
    <router-view v-slot="{ Component }">
      <keep-alive :exclude="['ReportEdit', 'DatasetEdit']">
        <component :is="Component" v-if="isReady" @click.stop="track('open')" />
      </keep-alive>
    </router-view>
    <!-- a comment -->
    <p :class="{ active: count > 0 }">{{ count * 2 }} items, {{ label.toUpperCase() }}</p>
    <input v-model.trim="label" #default>
  </AppProvider>
</template>

<script setup lang="ts">
import AppProvider from "@/components/AppProvider.vue";
import { computed, ref } from "vue";

const isReady = ref(false);
const count = ref<number>(0);
const label = computed(() => `${count.value} items`);

function track(event: string): void {
  console.log(event, count.value);
}
</script>

<style scoped lang="scss">
$gap: 8px;

.active {
  color: v-bind(color);
  margin: $gap;
}
</style>
