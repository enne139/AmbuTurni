import { MaterialCommunityIcons } from '@expo/vector-icons';
import { createBottomTabNavigator } from '@react-navigation/bottom-tabs';
import { createNativeStackNavigator } from '@react-navigation/native-stack';
import React from 'react';
import AssistezeListScreen from '../screens/assistenze/AssistezeListScreen';
import {
  AssistenzaDetailScreen,
  AssistenzaFormScreen,
} from '../screens/assistenze/AssistenzaScreens';
import ImpostazioniScreen from '../screens/impostazioni/ImpostazioniScreen';
import TurniListScreen from '../screens/turni/TurniListScreen';
import TurnoDetailScreen from '../screens/turni/TurnoDetailScreen';
import TurnoFormScreen from '../screens/turni/TurnoFormScreen';
import { colors } from '../utils/theme';

export type TurniStackParamList = {
  TurniList: undefined;
  TurnoDetail: { id: string };
  TurnoForm: { id?: string };
};

export type AssistenzeStackParamList = {
  AssistenzeList: undefined;
  AssistenzaDetail: { id: string };
  AssistenzaForm: { id?: string };
};

export type TabParamList = {
  Turni: undefined;
  Assistenze: undefined;
  Impostazioni: undefined;
};

const TurniStack = createNativeStackNavigator<TurniStackParamList>();
const AssistenzeStack = createNativeStackNavigator<AssistenzeStackParamList>();
const Tab = createBottomTabNavigator<TabParamList>();

const screenHeaderStyle = {
  headerStyle: { backgroundColor: colors.surface },
  headerTintColor: colors.textPrimary,
  contentStyle: { backgroundColor: colors.background },
} as const;

function TurniNavigator() {
  return (
    <TurniStack.Navigator screenOptions={screenHeaderStyle}>
      <TurniStack.Screen
        name="TurniList"
        component={TurniListScreen}
        options={{ title: 'Turni' }}
      />
      <TurniStack.Screen
        name="TurnoDetail"
        component={TurnoDetailScreen}
        options={{ title: 'Dettaglio turno' }}
      />
      <TurniStack.Screen
        name="TurnoForm"
        component={TurnoFormScreen}
        options={{ title: 'Turno' }}
      />
    </TurniStack.Navigator>
  );
}

function AssistenzeNavigator() {
  return (
    <AssistenzeStack.Navigator screenOptions={screenHeaderStyle}>
      <AssistenzeStack.Screen
        name="AssistenzeList"
        component={AssistezeListScreen}
        options={{ title: 'Assistenze' }}
      />
      <AssistenzeStack.Screen
        name="AssistenzaDetail"
        component={AssistenzaDetailScreen}
        options={{ title: 'Dettaglio assistenza' }}
      />
      <AssistenzeStack.Screen
        name="AssistenzaForm"
        component={AssistenzaFormScreen}
        options={{ title: 'Assistenza' }}
      />
    </AssistenzeStack.Navigator>
  );
}

export default function AppNavigator() {
  return (
    <Tab.Navigator
      screenOptions={{
        headerShown: false,
        tabBarStyle: { backgroundColor: colors.surface, borderTopColor: colors.border },
        tabBarActiveTintColor: colors.primary,
        tabBarInactiveTintColor: colors.textSecondary,
      }}
    >
      <Tab.Screen
        name="Turni"
        component={TurniNavigator}
        options={{
          tabBarIcon: ({ color, size }) => (
            <MaterialCommunityIcons name="ambulance" color={color} size={size} />
          ),
        }}
      />
      <Tab.Screen
        name="Assistenze"
        component={AssistenzeNavigator}
        options={{
          tabBarActiveTintColor: colors.secondary,
          tabBarIcon: ({ color, size }) => (
            <MaterialCommunityIcons name="account-heart" color={color} size={size} />
          ),
        }}
      />
      <Tab.Screen
        name="Impostazioni"
        component={ImpostazioniScreen}
        options={{
          headerShown: true,
          ...screenHeaderStyle,
          title: 'Impostazioni',
          tabBarIcon: ({ color, size }) => (
            <MaterialCommunityIcons name="cog" color={color} size={size} />
          ),
        }}
      />
    </Tab.Navigator>
  );
}
